#pragma once
// Auto-smooth: keeps presentation steady by trading render resolution and the frame cap against
// measured frame intervals, GPU time and iOS thermal state. Pure logic (no Metal, no UIKit) so it is
// tested on the CI host (Tests/smooth_governor.cpp). The renderer thread records; the app's main
// thread takes one window per second and steps the governor.
#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>

// Present-to-present intervals of one sampling window, in 0.5 ms buckets up to 125 ms.
struct PGPresentIntervalWindow {
	static constexpr size_t kBuckets = 251;	// last bucket: 125 ms and longer
	std::array<uint32_t, kBuckets> histogram{};
	uint32_t frames = 0;
	double totalMs = 0, maxMs = 0, gpuMs = 0;

	// Rejects non-finite, non-positive and background-length gaps (over 2 s) instead of counting them as stutter.
	bool record(double intervalMs) {
		if (!std::isfinite(intervalMs) || intervalMs <= 0 || intervalMs > 2000) return false;
		size_t bucket = std::min(kBuckets - 1, (size_t)(intervalMs * 2));
		histogram[bucket]++;
		frames++; totalMs += intervalMs; maxMs = std::max(maxMs, intervalMs);
		return true;
	}
	void addGPU(double ms) { if (std::isfinite(ms) && ms > 0 && ms < 1000) gpuMs += ms; }
	double meanMs() const { return frames ? totalMs / frames : 0; }
	double gpuMsPerFrame() const { return frames ? gpuMs / frames : 0; }
	// Upper edge of the bucket holding the p-th interval (the overflow bucket reports the true maximum).
	double percentile(double p) const {
		if (!frames) return 0;
		uint64_t target = (uint64_t)std::ceil(frames * std::clamp(p, 0.0, 1.0)), count = 0;
		if (!target) target = 1;
		for (size_t i = 0; i < kBuckets; i++) {
			count += histogram[i];
			if (count >= target) return i == kBuckets - 1 ? maxMs : (i + 1) * 0.5;
		}
		return maxMs;
	}
	// Fraction of intervals whose bucket lies wholly at or above thresholdMs.
	double fractionAtLeast(double thresholdMs) const {
		if (!frames || !std::isfinite(thresholdMs)) return 0;
		size_t first = (size_t)std::ceil(std::max(0.0, thresholdMs) * 2);
		uint64_t late = 0;
		for (size_t i = std::min(first, kBuckets - 1); i < kBuckets; i++) late += histogram[i];
		if (first >= kBuckets) late = maxMs >= thresholdMs ? histogram[kBuckets - 1] : 0;
		return (double)late / frames;
	}
	void reset() { histogram.fill(0); frames = 0; totalMs = maxMs = gpuMs = 0; }
};

struct PGSmoothSample {
	uint32_t frames = 0;
	double p95Ms = 0, lateFraction = 0, gpuMsPerFrame = 0;
	int thermal = 0;		// NSProcessInfoThermalState: 0 nominal, 1 fair, 2 serious, 3 critical
};

// Engine frame-limit codes as PGSetFrameLimit takes them: 0 off (screen rate), 1 = 60 FPS, 2 = 30 FPS.
struct PGSmoothGovernor {
	// configuration
	int userLimit = 1;			// the player's own cap: never exceeded
	double displayHz = 60;
	int minScale = 550, maxScale = 1000;	// permille of the chosen render height
	// state
	int scale = 1000, limit = 1;
	int badRun = 0, goodRun = 0, cooldown = 0;
	int upHold = kBaseUpHold, sinceUp = 1000, stableRun = 0;
	bool lastWasUp = false;
	static constexpr int kBaseUpHold = 6, kMaxUpHold = 64;

	static int clampLimit(int code) { return code == 0 || code == 1 || code == 2 ? code : 1; }
	double fpsFor(int code) const {
		double hz = std::isfinite(displayHz) && displayHz >= 30 ? displayHz : 60;
		return code == 2 ? std::min(30.0, hz) : code == 1 ? std::min(60.0, hz) : hz;
	}
	double targetMs() const { return 1000.0 / fpsFor(limit); }
	// Present pacing for the current cap: hold each frame for 1/cap when the cap is below the screen rate.
	double presentInterval() const { double f = fpsFor(limit); return f + 0.5 < fpsFor(0) ? 1.0 / f : 0; }

	void configure(int playerLimit, double hz, int minScalePermille) {
		userLimit = clampLimit(playerLimit);
		displayHz = std::isfinite(hz) && hz >= 30 && hz <= 240 ? hz : 60;
		minScale = std::clamp(minScalePermille, 300, 1000);
		maxScale = 1000; scale = 1000; limit = userLimit;
		badRun = goodRun = cooldown = stableRun = 0; upHold = kBaseUpHold; sinceUp = 1000; lastWasUp = false;
	}

	// The next more restrictive cap (lower FPS), or -1. On a 60 Hz screen "off" and "60" are the same rate.
	int lowerLimit(int code) const {
		for (int c = code + 1; c <= 2; c++) if (fpsFor(c) + 0.5 < fpsFor(code)) return c;
		return -1;
	}
	// The next less restrictive cap that the player allows, or -1.
	int higherLimit(int code) const {
		for (int c = code - 1; c >= userLimit; c--) if (fpsFor(c) > fpsFor(code) + 0.5) return c;
		return -1;
	}

	static int thermalScaleCeiling(int thermal) { return thermal >= 3 ? 650 : thermal == 2 ? 800 : 1000; }
	// The least restrictive cap allowed at this heat: serious holds 60 at most, critical holds 30.
	int thermalLimitFloor(int thermal) const {
		int code = userLimit;
		if (thermal >= 2) while (fpsFor(code) > 60.5 && lowerLimit(code) >= 0) code = lowerLimit(code);
		if (thermal >= 3) while (lowerLimit(code) >= 0) code = lowerLimit(code);
		return code;
	}

	// One window (about a second). Returns true when scale or limit changed.
	bool step(const PGSmoothSample &s) {
		if (s.frames < 15) return false;	// loading, paused or backgrounded: no evidence either way
		sinceUp++;

		// Heat first: ceilings apply at once, without waiting for frames to go late.
		int ceiling = std::max(minScale, thermalScaleCeiling(s.thermal));
		int floorLimit = thermalLimitFloor(s.thermal);
		bool forced = false;
		if (scale > ceiling) { scale = ceiling; forced = true; }
		if (fpsFor(limit) > fpsFor(floorLimit) + 0.5) { limit = floorLimit; forced = true; }
		if (forced) { cooldown = 2; badRun = goodRun = 0; lastWasUp = false; return true; }
		if (cooldown > 0) { cooldown--; return false; }

		double target = targetMs();
		double gpuLoad = target > 0 ? s.gpuMsPerFrame / target : 0;
		bool bad = s.lateFraction > 0.08 || s.p95Ms > target * 1.30;
		bool good = s.lateFraction < 0.02 && s.p95Ms <= target * 1.15;
		if (bad) { badRun++; goodRun = 0; stableRun = 0; }
		else if (good) { goodRun++; badRun = 0; stableRun++; }
		else { badRun = 0; goodRun = 0; stableRun = 0; }

		// A raise that turned bad soon after is remembered: wait longer before the next one.
		if (bad && lastWasUp && sinceUp <= 5) { upHold = std::min(kMaxUpHold, upHold * 2); lastWasUp = false; }
		if (stableRun >= 30 && upHold > kBaseUpHold) { upHold = std::max(kBaseUpHold, upHold / 2); stableRun = 0; }

		if (badRun >= 2) {
			badRun = 0; cooldown = 3; lastWasUp = false;
			// GPU-bound: fewer pixels help. Otherwise (game thread bound) or already at the lowest
			// resolution, a lower cap is what makes the remaining frames even.
			if (gpuLoad >= 0.75 && scale > minScale) { scale = std::max(minScale, roundScale(scale * 0.88)); return true; }
			int lower = lowerLimit(limit);
			if (lower >= 0) { limit = lower; return true; }
			if (scale > minScale) { scale = std::max(minScale, roundScale(scale * 0.88)); return true; }
			cooldown = 0;
			return false;
		}
		if (goodRun >= upHold) {
			goodRun = 0;
			int higher = higherLimit(limit);
			// A higher cap needs at least twice the GPU headroom; resolution comes back first.
			if (scale < ceiling && gpuLoad < 0.65) {
				scale = std::min(ceiling, roundScale(scale * 1.06) + 10);
				cooldown = 3; lastWasUp = true; sinceUp = 0; return true;
			}
			if (higher >= 0 && higher >= floorLimit && gpuLoad * fpsFor(higher) / fpsFor(limit) < 0.80) {
				limit = higher; cooldown = 3; lastWasUp = true; sinceUp = 0; return true;
			}
		}
		return false;
	}

private:
	static int roundScale(double v) { return (int)(v / 10.0) * 10; }
};
