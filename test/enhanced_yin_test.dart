import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonisync_solfege_trainer/services/enhanced_yin.dart';

Uint8List _genSinePcm16(double f, int sr, int n, {double amp = 0.5, double noise = 0.0}) {
	final bytes = Uint8List(n * 2);
	final view = ByteData.sublistView(bytes);
	final rnd = Random(42);
	for (int i = 0; i < n; i++) {
		final t = i / sr;
		double s = amp * sin(2 * pi * f * t);
		if (noise > 0) s += (rnd.nextDouble() * 2 - 1) * noise;
		s = s.clamp(-1.0, 1.0);
		final v = (s * 32767).round();
		view.setInt16(i * 2, v, Endian.little);
	}
	return bytes;
}

void main() {
	test('Detects ~440 Hz after a few frames', () {
		const sr = 44100;
		const frame = 2048;
		final enh = EnhancedYin(sampleRate: sr, wienerStrength: 0.5, vadSensitivity: 0.6, medianWindow: 5);

		double? last;
		for (int i = 0; i < 12; i++) {
			final data = _genSinePcm16(440, sr, frame, amp: 0.5, noise: 0.02);
			last = enh.processFrame(data, sr);
		}
		expect(last, isNotNull);
		expect(last!, inInclusiveRange(420, 460));
	});

	test('Silence yields null (no voice)', () {
		const sr = 44100;
		const frame = 2048;
		final enh = EnhancedYin(sampleRate: sr);

		double? any;
		for (int i = 0; i < 10; i++) {
			final silence = Uint8List(frame * 2); // zeros
			any = enh.processFrame(silence, sr);
		}
		expect(any, isNull);
	});
} 