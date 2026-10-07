package ie.xav.tetherlink

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update

/** Live service state the setup screen observes (same process as TetherService). */
object TetherState {
    data class Snapshot(
        val running: Boolean = false,
        val advertising: Boolean = false,
        val hotspot: Byte = 0,
        val connectedMacs: Int = 0,
    )

    private val state = MutableStateFlow(Snapshot())
    val snapshot: StateFlow<Snapshot> = state.asStateFlow()

    fun update(change: (Snapshot) -> Snapshot) = state.update(change)
}
