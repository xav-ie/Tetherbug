package ie.xav.tetherlink

import android.annotation.SuppressLint
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothGattServer
import android.bluetooth.BluetoothGattServerCallback
import android.bluetooth.BluetoothGattService
import android.bluetooth.BluetoothManager
import android.bluetooth.le.AdvertisingSet
import android.bluetooth.le.AdvertisingSetCallback
import android.bluetooth.le.AdvertisingSetParameters
import android.bluetooth.le.AdvertiseData
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ServiceInfo
import android.net.wifi.WifiManager
import android.os.BatteryManager
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.ParcelUuid
import android.telephony.TelephonyManager
import android.util.Log
import java.util.UUID
import java.util.concurrent.Executors

/**
 * Foreground service exposing the tether-link BLE GATT service (see README "BLE protocol").
 * Both characteristics require an encrypted link, so only a bonded Mac can read status or send
 * commands; the advertisement carries nothing but the service UUID.
 */
@SuppressLint("MissingPermission") // MainActivity grants BLUETOOTH_CONNECT/ADVERTISE before starting us.
class TetherService : Service() {
    companion object {
        private const val TAG = "tether-link"
        val SERVICE: UUID = UUID.fromString("1581bac4-33fe-43a8-b97f-5dd7a01f48c9")
        val STATUS: UUID = UUID.fromString("90766fca-8a24-43ae-8501-3dcef06a8479")
        val COMMAND: UUID = UUID.fromString("e036426f-6317-487d-8777-e6f6d91f8a4d")
        val CREDENTIALS: UUID = UUID.fromString("355534b0-7222-480b-aa18-02a6c30feea2")
        private val CCCD: UUID = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")

        private const val PROTOCOL_VERSION: Byte = 2
        private const val FLAG_CONTROLLABLE = 1
        private const val CMD_ENABLE: Byte = 0x01
        private const val CMD_DISABLE: Byte = 0x02

        // Hidden WifiManager AP-state broadcast and its states.
        private const val WIFI_AP_STATE_CHANGED = "android.net.wifi.WIFI_AP_STATE_CHANGED"
        private const val EXTRA_WIFI_AP_STATE = "wifi_state"
        private const val AP_ENABLING = 12
        private const val AP_ENABLED = 13
        private const val AP_FAILED = 14

        // Status hotspot byte.
        private const val HOTSPOT_OFF: Byte = 0
        private const val HOTSPOT_STARTING: Byte = 1
        private const val HOTSPOT_ON: Byte = 2
        private const val HOTSPOT_FAILED: Byte = 3
    }

    private val worker = Executors.newSingleThreadExecutor()
    private val subscribers = mutableSetOf<BluetoothDevice>()
    private lateinit var gatt: BluetoothGattServer
    private lateinit var statusChar: BluetoothGattCharacteristic
    private val connected = mutableSetOf<BluetoothDevice>()
    private val handler = Handler(Looper.getMainLooper())
    private var hotspot = HOTSPOT_OFF
        set(value) {
            field = value
            TetherState.update { it.copy(hotspot = value) }
        }
    private var battery = 0

    private val receiver =
        object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                when (intent.action) {
                    WIFI_AP_STATE_CHANGED -> hotspot = hotspotState(intent.getIntExtra(EXTRA_WIFI_AP_STATE, 0))
                    Intent.ACTION_BATTERY_CHANGED -> {
                        val level = intent.getIntExtra(BatteryManager.EXTRA_LEVEL, 0)
                        val scale = intent.getIntExtra(BatteryManager.EXTRA_SCALE, 100)
                        val percent = level * 100 / scale
                        if (percent == battery) return
                        battery = percent
                    }
                }
                notifySubscribers()
            }
        }

    private fun hotspotState(apState: Int) =
        when (apState) {
            AP_ENABLING -> HOTSPOT_STARTING
            AP_ENABLED -> HOTSPOT_ON
            AP_FAILED -> HOTSPOT_FAILED
            else -> HOTSPOT_OFF
        }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        startForeground(1, notification(), ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE)
        // The AP-state broadcast isn't sticky, so read the current state once.
        hotspot = hotspotState(Privileged.apState(getSystemService(WifiManager::class.java)))
        registerReceiver(receiver, IntentFilter(WIFI_AP_STATE_CHANGED).apply { addAction(Intent.ACTION_BATTERY_CHANGED) })

        val manager = getSystemService(BluetoothManager::class.java)
        gatt = manager.openGattServer(this, callback)
        statusChar =
            BluetoothGattCharacteristic(
                STATUS,
                BluetoothGattCharacteristic.PROPERTY_READ or BluetoothGattCharacteristic.PROPERTY_NOTIFY,
                BluetoothGattCharacteristic.PERMISSION_READ_ENCRYPTED,
            ).apply {
                addDescriptor(
                    BluetoothGattDescriptor(
                        CCCD,
                        BluetoothGattDescriptor.PERMISSION_READ_ENCRYPTED or BluetoothGattDescriptor.PERMISSION_WRITE_ENCRYPTED,
                    ),
                )
            }
        val commandChar =
            BluetoothGattCharacteristic(
                COMMAND,
                BluetoothGattCharacteristic.PROPERTY_WRITE,
                BluetoothGattCharacteristic.PERMISSION_WRITE_ENCRYPTED,
            )
        // The hotspot password, so the Mac can show it; like everything else, only over a bonded, encrypted link.
        val credentialsChar =
            BluetoothGattCharacteristic(
                CREDENTIALS,
                BluetoothGattCharacteristic.PROPERTY_READ,
                BluetoothGattCharacteristic.PERMISSION_READ_ENCRYPTED,
            )
        gatt.addService(
            BluetoothGattService(SERVICE, BluetoothGattService.SERVICE_TYPE_PRIMARY).apply {
                addCharacteristic(statusChar)
                addCharacteristic(commandChar)
                addCharacteristic(credentialsChar)
            },
        )

        TetherState.update { it.copy(running = true) }
        startAdvertising()
        pollHotspot()
    }

    /** The AP-state broadcast isn't reliably delivered, so also check the real state every few seconds. */
    private fun pollHotspot() {
        handler.postDelayed({
            val actual = hotspotState(Privileged.apState(getSystemService(WifiManager::class.java)))
            if (actual != hotspot && hotspot != HOTSPOT_FAILED) {
                hotspot = actual
                notifySubscribers()
            }
            pollHotspot()
        }, 3000)
    }

    private fun startAdvertising() {
        // ponytail: null while Bluetooth is off; advertising starts with the next service start.
        val advertiser = getSystemService(BluetoothManager::class.java).adapter.bluetoothLeAdvertiser
            ?: return Log.w(TAG, "Bluetooth is off; not advertising").let {}
        TetherState.update { it.copy(advertising = false) }
        advertiser.startAdvertisingSet(
            AdvertisingSetParameters.Builder()
                .setLegacyMode(true)
                .setConnectable(true)
                .setScannable(true)
                .setInterval(AdvertisingSetParameters.INTERVAL_HIGH)
                .setTxPowerLevel(AdvertisingSetParameters.TX_POWER_MEDIUM)
                .build(),
            AdvertiseData.Builder().addServiceUuid(ParcelUuid(SERVICE)).build(),
            null,
            null,
            null,
            advertiseCallback,
        )
        // The stack can silently drop a request (seen right after a reinstall), so retry
        // until it reports the set started.
        handler.postDelayed({
            if (!TetherState.snapshot.value.advertising) {
                Log.w(TAG, "advertising didn't start; retrying")
                advertiser.stopAdvertisingSet(advertiseCallback)
                startAdvertising()
            }
        }, 5000)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int) = START_STICKY

    override fun onDestroy() {
        handler.removeCallbacksAndMessages(null)
        getSystemService(BluetoothManager::class.java).adapter.bluetoothLeAdvertiser?.stopAdvertisingSet(advertiseCallback)
        TetherState.update { TetherState.Snapshot() }
        gatt.close()
        unregisterReceiver(receiver)
        worker.shutdown()
        super.onDestroy()
    }

    private fun status(): ByteArray {
        val signal = getSystemService(TelephonyManager::class.java).signalStrength?.level ?: 0
        val ssid = runCatching { Privileged.ssid() }.getOrNull().orEmpty()
        val flags = if (Privileged.isReady()) FLAG_CONTROLLABLE else 0
        return byteArrayOf(PROTOCOL_VERSION, hotspot, battery.toByte(), signal.toByte(), flags.toByte()) + ssid.toByteArray()
    }

    private fun notifySubscribers() {
        if (synchronized(subscribers) { subscribers.isEmpty() }) return
        worker.execute {
            val value = status()
            synchronized(subscribers) { subscribers.toList() }.forEach { gatt.notifyCharacteristicChanged(it, statusChar, false, value) }
        }
    }

    private fun command(cmd: Byte) {
        if (!Privileged.isReady()) {
            Log.w(TAG, "command $cmd ignored: Shizuku not ready")
            hotspot = HOTSPOT_FAILED
            notifySubscribers()
            return
        }
        val enable = cmd == CMD_ENABLE
        if (hotspot == (if (enable) HOTSPOT_ON else HOTSPOT_OFF)) return notifySubscribers()
        Privileged.setHotspot(enable) { result ->
            if (result != 0) {
                Log.w(TAG, "tethering ${if (enable) "start" else "stop"} failed: $result")
                val actual = hotspotState(Privileged.apState(getSystemService(WifiManager::class.java)))
                // Rejected but already in the requested state (e.g. a duplicate enable) isn't a failure.
                hotspot = if (actual == (if (enable) HOTSPOT_ON else HOTSPOT_OFF)) actual else HOTSPOT_FAILED
                notifySubscribers()
            }
        }
    }

    private val callback =
        object : BluetoothGattServerCallback() {
            override fun onConnectionStateChange(device: BluetoothDevice, status: Int, newState: Int) {
                if (newState != BluetoothGatt.STATE_CONNECTED) synchronized(subscribers) { subscribers.remove(device) }
                val count =
                    synchronized(connected) {
                        if (newState == BluetoothGatt.STATE_CONNECTED) connected.add(device) else connected.remove(device)
                        connected.size
                    }
                TetherState.update { it.copy(connectedMacs = count) }
            }

            override fun onCharacteristicReadRequest(device: BluetoothDevice, requestId: Int, offset: Int, characteristic: BluetoothGattCharacteristic) {
                worker.execute {
                    val value =
                        when (characteristic.uuid) {
                            STATUS -> status()
                            CREDENTIALS -> runCatching { Privileged.passphrase() }.getOrDefault("").toByteArray()
                            else -> null
                        }
                    val ok = value != null && offset <= value.size
                    gatt.sendResponse(
                        device,
                        requestId,
                        if (ok) BluetoothGatt.GATT_SUCCESS else BluetoothGatt.GATT_FAILURE,
                        offset,
                        if (ok) value!!.copyOfRange(offset, value.size) else null,
                    )
                }
            }

            override fun onCharacteristicWriteRequest(
                device: BluetoothDevice,
                requestId: Int,
                characteristic: BluetoothGattCharacteristic,
                preparedWrite: Boolean,
                responseNeeded: Boolean,
                offset: Int,
                value: ByteArray,
            ) {
                val ok = characteristic.uuid == COMMAND && value.size == 1 && value[0] in listOf(CMD_ENABLE, CMD_DISABLE)
                if (responseNeeded) {
                    gatt.sendResponse(device, requestId, if (ok) BluetoothGatt.GATT_SUCCESS else BluetoothGatt.GATT_FAILURE, 0, null)
                }
                if (ok) worker.execute { command(value[0]) }
            }

            override fun onDescriptorWriteRequest(
                device: BluetoothDevice,
                requestId: Int,
                descriptor: BluetoothGattDescriptor,
                preparedWrite: Boolean,
                responseNeeded: Boolean,
                offset: Int,
                value: ByteArray,
            ) {
                synchronized(subscribers) {
                    if (value.contentEquals(BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE)) subscribers.add(device) else subscribers.remove(device)
                }
                if (responseNeeded) gatt.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, 0, null)
            }
        }

    private val advertiseCallback =
        object : AdvertisingSetCallback() {
            override fun onAdvertisingSetStarted(advertisingSet: AdvertisingSet?, txPower: Int, status: Int) {
                if (status == ADVERTISE_SUCCESS) {
                    TetherState.update { it.copy(advertising = true) }
                } else {
                    Log.e(TAG, "advertising failed: $status")
                }
            }
        }

    private fun notification(): Notification {
        val channel = NotificationChannel("service", "TetherLink", NotificationManager.IMPORTANCE_MIN)
        getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        return Notification.Builder(this, channel.id)
            .setSmallIcon(R.drawable.ic_stat_tether)
            .setContentTitle("TetherLink")
            .setContentText("Ready to share the hotspot with your Mac")
            .setOngoing(true)
            .build()
    }
}
