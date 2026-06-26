#include <algorithm>
#include "../../ModConfiguration.h"
#include "Player.h"

namespace HRZR
{
	// In the slow-motion concentration aiming state the engine scales the per-frame mouse look delta by the slowed
	// frame delta-time, so effective sensitivity drops to roughly aimed_sensitivity * timescale. The game compensates
	// for this on the motion/gyro path (MotionAimingSlomoSensitivityModifier) but not on the mouse path. We cancel the
	// drop by inverse-scaling the processed mouse look vector before the camera consumes it.
	//
	// FUN_140f735b0 is the camera look application. It takes the camera in rcx and the (slowed) frame delta-time in
	// xmm1. The aim/look controller lives at Player + 0x138 (see PlayerGame::GetMouseLookInput); its processed look
	// vector is the float2 at controller + 0x4790. We gate solely on the world being slowed: concentration is an
	// aiming-only state, so timescale < 1 with a live look controller already implies the player is aiming.
	constexpr ptrdiff_t kAimControllerOffset = 0x138;
	constexpr ptrdiff_t kLookInputOffset = 0x4790;

	void (*OriginalUpdateCameraLook)(void *Camera, float DeltaTime);
	void HookedUpdateCameraLook(void *Camera, float DeltaTime)
	{
		const float correction = ModConfiguration.ConcentrationSensitivityCorrection;
		const float timeScale = GameModule::GetInstance()->m_WorldTimeScale;

		auto player = Player::GetLocalPlayer();
		auto controller = player ? *reinterpret_cast<uint8_t **>(reinterpret_cast<uint8_t *>(player) + kAimControllerOffset) : nullptr;

		const bool slowMotion = timeScale < 1.0f;
		float k = 1.0f;

		if (correction > 0.0f && slowMotion && controller)
		{
			const float t = std::max(timeScale, 0.05f);
			k = 1.0f + correction * (1.0f / t - 1.0f);

			reinterpret_cast<float *>(controller + kLookInputOffset)[0] *= k;
			reinterpret_cast<float *>(controller + kLookInputOffset)[1] *= k;
		}

		// Observability: throttled to one line every 30 update frames. Lets us tell whether a failure is in detection
		// (timescale / player / controller / aim flags never reaching the expected values) or in the look scaling
		// itself (look values wrong or having no felt effect). The logged look vector is post-scale; divide by k for
		// the pre-scale value. Set ConcentrationSensitivityCorrection = 0 to observe vanilla behavior without scaling.
		if (ModConfiguration.EnableConcentrationSensitivityLogging)
		{
			static int throttle = 0;
			if (throttle++ % 30 == 0)
			{
				auto look = controller ? reinterpret_cast<float *>(controller + kLookInputOffset) : nullptr;
				spdlog::debug(
					"ConcSens ts={:.3f} slowmo={} player={} ctrl={} k={:.3f} look=({:.4f},{:.4f})",
					timeScale, slowMotion, static_cast<void *>(player), static_cast<void *>(controller), k,
					look ? look[0] : 0.0f, look ? look[1] : 0.0f);
			}
		}

		OriginalUpdateCameraLook(Camera, DeltaTime);
	}

	DECLARE_HOOK_TRANSACTION(ConcentrationSensitivity)
	{
		// Install for the fix, or for observation-only mode (logging on, correction 0).
		if (ModConfiguration.ConcentrationSensitivityCorrection > 0.0f || ModConfiguration.EnableConcentrationSensitivityLogging)
			Hooks::WriteJump(
				Offsets::Signature("48 8B C4 57 48 81 EC 30 01 00 00 C5 78 29 48 98 48 8B F9"),
				&HookedUpdateCameraLook,
				&OriginalUpdateCameraLook);
	};
}
