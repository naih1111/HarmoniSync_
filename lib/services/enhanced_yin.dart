import 'dart:typed_data';
import 'dart:math';

import 'wiener_filter.dart';
import 'voice_activity_detector.dart';
import 'pitch_smoother.dart';
import 'yin_algorithm.dart';

/// Drop-in enhancement wrapper around YinAlgorithm.
///
/// Steps per frame:
/// 1) Wiener-like noise reduction (time-domain, lightweight)
/// 2) Voice Activity Detection (energy + ZCR)
/// 3) Optional: upsample to increase effective resolution
/// 4) YIN pitch detection on cleaned PCM16 bytes
/// 5) Optional: parabolic refinement around detected lag
/// 6) Median smoothing across recent frames
class EnhancedYin {
	final WienerFilter _wiener;
	final VoiceActivityDetector _vad;
	final PitchSmoother _smoother;

	/// Upsampling factor before calling Yin (1 = disabled, 2 = 2x, etc.).
	final int upsampleFactor;

	/// Enable parabolic refinement around detected period for sub-sample accuracy.
	final bool enableParabolicRefinement;

	EnhancedYin({
		required int sampleRate,
		double wienerStrength = 0.5,
		double vadSensitivity = 0.6,
		int medianWindow = 5,
		int upsampleFactor = 1,
		bool enableParabolicRefinement = true,
	})  : _wiener = WienerFilter(strength: wienerStrength),
			_vad = VoiceActivityDetector(sampleRate: sampleRate, sensitivity: vadSensitivity),
			_smoother = PitchSmoother(windowSize: medianWindow),
			upsampleFactor = upsampleFactor < 1 ? 1 : upsampleFactor,
			enableParabolicRefinement = enableParabolicRefinement;

	/// Processes one PCM16 little-endian frame. Returns smoothed pitch (Hz) or null
	/// if no voice is detected.
	double? processFrame(Uint8List audioData, int sampleRate) {
		// 1) Noise reduction on the PCM16 frame.
		final Float64List cleaned = _wiener.apply(audioData);

		// 2) Voice Activity Detection on cleaned samples.
		final bool isVoice = _vad.isVoice(cleaned);
		if (!isVoice) {
			_wiener.updateNoiseFromNonVoice(cleaned);
			// Keep smoother history intact but report no pitch for this frame.
			_smoother.add(null);
			return null;
		}

		// 3) Optional upsampling for better resolution.
		final int srForYin = sampleRate * upsampleFactor;
		final Float64List bufferForYin = upsampleFactor == 1
				? cleaned
				: _upsampleLinear(cleaned, upsampleFactor);

		// 4) Convert float samples to PCM16 and run Yin.
		final Uint8List cleanedPcm = _float64ToPcm16(bufferForYin);
		final double? basePitch = YinAlgorithm.detectPitch(cleanedPcm, srForYin);
		if (basePitch == null || !enableParabolicRefinement) {
			return _smoother.add(basePitch);
		}

		// 5) Parabolic refinement around detected period using the same buffer fed to Yin.
		final double refined = _refinePitchParabolic(bufferForYin, srForYin, basePitch);

		// 6) Smooth across frames.
		return _smoother.add(refined);
	}

	Uint8List _float64ToPcm16(Float64List samples) {
		final int length = samples.length;
		final Uint8List bytes = Uint8List(length * 2);
		final ByteData view = ByteData.sublistView(bytes);
		for (int i = 0; i < length; i++) {
			double s = samples[i];
			if (s.isNaN || !s.isFinite) s = 0.0;
			s = s.clamp(-1.0, 1.0);
			final int v = (s * 32767.0).round();
			view.setInt16(i * 2, v, Endian.little);
		}
		return bytes;
	}

	Float64List _upsampleLinear(Float64List x, int factor) {
		if (factor <= 1 || x.length < 2) return x;
		final int n = x.length;
		final int m = (n - 1) * factor + 1;
		final Float64List y = Float64List(m);
		for (int i = 0; i < n - 1; i++) {
			final double a = x[i];
			final double b = x[i + 1];
			for (int k = 0; k < factor; k++) {
				final double t = k / factor;
				y[i * factor + k] = a + (b - a) * t;
			}
		}
		y[m - 1] = x[n - 1];
		return y;
	}

	/// Compute a local squared-difference around lag = sr / f0 and apply parabolic interpolation.
	double _refinePitchParabolic(Float64List x, int sr, double f0) {
		final double tau0 = max(2.0, sr / max(1e-6, f0));
		int tau = tau0.round();
		final int maxLag = x.length ~/ 2;
		if (tau < 1 || tau >= maxLag - 1) return f0;

		double d(int lag) {
			double sum = 0.0;
			final int limit = x.length - lag;
			for (int i = 0; i < limit; i++) {
				final double diff = x[i] - x[i + lag];
				sum += diff * diff;
			}
			return sum;
		}

		final double d0 = d(tau);
		final double dM = d(tau - 1);
		final double dP = d(tau + 1);
		final double denom = (dM - 2.0 * d0 + dP);
		double tauRefined = tau.toDouble();
		if (denom.abs() > 1e-12) {
			tauRefined = tau + 0.5 * (dM - dP) / denom;
		}
		if (!tauRefined.isFinite || tauRefined < 1.0) return f0;
		return sr / tauRefined;
	}
} 