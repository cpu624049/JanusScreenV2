import 'dart:ui';
import 'dart:typed_data';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:google_ml_kit/google_ml_kit.dart';
import 'package:battery_plus/battery_plus.dart';

void main() {
	runApp(const PrivacyApp());
}

class PrivacyApp extends StatelessWidget {
	const PrivacyApp({super.key});

	@override
	Widget build(BuildContext context) {
		final base = ThemeData(
			colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF3B82F6)),
			useMaterial3: true,
		);
		return MaterialApp(
			title: 'Privacy Foveation Prototype',
			debugShowCheckedModeBanner: false,
			theme: base.copyWith(
				cardTheme: CardThemeData(
					shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
					elevation: 2,
					margin: EdgeInsets.zero,
				),
				listTileTheme: const ListTileThemeData(
					dense: false,
					contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
				),
				appBarTheme: const AppBarTheme(
					surfaceTintColor: Colors.transparent,
				),
			),
			home: const HomePage(),
		);
	}
}

class HomePage extends StatefulWidget {
	const HomePage({super.key});

	@override
	State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
	bool _privacyEnabled = false;
	bool _shaderEnabled = true;
	bool _cameraEnabled = false;
	Offset _focusCenter = Offset.zero;
	double _focusRadius = 140;
	double _blurSigma = 9;
	double _grain = 0.22;
	double _patternType = 0.0; // 0=noise, 1=hatch, 2=dot, 3=wave

	// Perf/Battery
	bool _lowPower = false;
	int _mlMinIntervalMs = 120; // 최소 간격(ms) - 약 8~15fps
	DateTime? _lastMl;
	Battery? _battery;
	int _batteryLevel = 100;
	BatteryState _batteryState = BatteryState.unknown;
	Timer? _batteryTimer;

	FragmentProgram? _program;
	Shader? _shader;
	CameraController? _cameraController;
	List<CameraDescription>? _cameras;
	FaceDetector? _faceDetector;
	bool _isProcessingFrame = false;

	@override
	void initState() {
		super.initState();
		WidgetsBinding.instance.addObserver(this);
	}

	@override
	void didChangeDependencies() {
		super.didChangeDependencies();
		_loadShader();
		_initCamera();
		_initBatteryMonitoring();
	}

	@override
	void dispose() {
		WidgetsBinding.instance.removeObserver(this);
		_cameraController?.dispose();
		_faceDetector?.close();
		_batteryTimer?.cancel();
		super.dispose();
	}

	@override
	void didChangeAppLifecycleState(AppLifecycleState state) {
		if (_cameraController == null) return;
		switch (state) {
			case AppLifecycleState.inactive:
			case AppLifecycleState.paused:
				if (_cameraController!.value.isStreamingImages) {
					_cameraController!.stopImageStream();
				}
				break;
			case AppLifecycleState.resumed:
				if (_cameraEnabled && !_cameraController!.value.isStreamingImages) {
					_cameraController!.startImageStream(_processCameraFrame);
				}
				break;
			case AppLifecycleState.detached:
				break;
			default:
				break;
		}
	}

	Future<void> _initCamera() async {
		try {
			_cameras = await availableCameras();
			if (_cameras!.isNotEmpty) {
				await _requestCameraPermission();
			}
		} catch (e) {
			debugPrint('Camera initialization failed: $e');
		}
	}

	Future<void> _requestCameraPermission() async {
		final status = await Permission.camera.request();
		if (status.isGranted && _cameras!.isNotEmpty) {
			await _startCamera();
		}
	}

	Future<void> _startCamera() async {
		try {
			_cameraController = CameraController(
				_cameras!.first,
				ResolutionPreset.medium,
				enableAudio: false,
			);
			await _cameraController!.initialize();
			
			_faceDetector = GoogleMlKit.vision.faceDetector(
				FaceDetectorOptions(
					enableContours: true,
					enableLandmarks: true,
					enableClassification: false,
					enableTracking: true,
					minFaceSize: 0.1,
				),
			);
			
			_cameraController!.startImageStream(_processCameraFrame);
			
			if (mounted) {
				setState(() => _cameraEnabled = true);
			}
		} catch (e) {
			debugPrint('Camera start failed: $e');
		}
	}

	Future<void> _processCameraFrame(CameraImage image) async {
		if (_isProcessingFrame || !_cameraEnabled || _faceDetector == null) return;
		// 저전력: 최소 간격 미만이면 스킵
		final now = DateTime.now();
		if (_lastMl != null && now.difference(_lastMl!).inMilliseconds < _mlMinIntervalMs) {
			return;
		}
		_lastMl = now;

		_isProcessingFrame = true;
		try {
			final inputImage = _inputImageFromCameraImage(image);
			if (inputImage == null) return;
			final faces = await _faceDetector!.processImage(inputImage);
			if (faces.isNotEmpty && mounted) {
				_updateFocusFromFace(faces.first);
			}
		} catch (e) {
			debugPrint('Face detection failed: $e');
		} finally {
			_isProcessingFrame = false;
		}
	}

	Future<void> _initBatteryMonitoring() async {
		_battery = Battery();
		await _updateBatteryInfo();
		
		// 배터리 상태를 주기적으로 체크 (30초마다)
		_batteryTimer = Timer.periodic(const Duration(seconds: 30), (_) {
			_updateBatteryInfo();
		});
	}

	Future<void> _updateBatteryInfo() async {
		try {
			final level = await _battery!.batteryLevel;
			final state = await _battery!.batteryState;
			
			if (mounted) {
				setState(() {
					_batteryLevel = level;
					_batteryState = state;
					_updatePerformanceSettings();
				});
			}
		} catch (e) {
			debugPrint('Battery info update failed: $e');
		}
	}

	void _updatePerformanceSettings() {
		// 배터리 상태에 따른 성능 조절
		if (_batteryLevel < 20 || _batteryState == BatteryState.charging) {
			// 저전력 모드: ML 처리 간격 증가, 쉐이더 비활성화
			_mlMinIntervalMs = 200; // 약 5fps
			_lowPower = true;
		} else if (_batteryLevel < 50) {
			// 중간 모드: ML 처리 간격 중간
			_mlMinIntervalMs = 150; // 약 6.7fps
			_lowPower = false;
		} else {
			// 고성능 모드: ML 처리 간격 최소
			_mlMinIntervalMs = 100; // 약 10fps
			_lowPower = false;
		}
	}

	void _showPrivacyInfo(BuildContext context) {
		showDialog(
			context: context,
			builder: (context) => AlertDialog(
				title: const Row(
					children: [
						Icon(Icons.privacy_tip_outlined),
						SizedBox(width: 8),
						Text('개인정보 보호 안내'),
					],
				),
				content: const SingleChildScrollView(
					child: Column(
						crossAxisAlignment: CrossAxisAlignment.start,
						mainAxisSize: MainAxisSize.min,
						children: [
							Text(
								'🔒 프라이버시 모드',
								style: TextStyle(fontWeight: FontWeight.bold),
							),
							SizedBox(height: 8),
							Text('• 화면 주변부를 흐리게 처리하여 옆 사람이 내용을 보기 어렵게 합니다'),
							Text('• 물리적 프라이버시 필름과 달리 소프트웨어로 구현됩니다'),
							Text('• 완전한 차단은 불가능하며, 가독성 저하가 목적입니다'),
							SizedBox(height: 16),
							Text(
								'📷 카메라 사용',
								style: TextStyle(fontWeight: FontWeight.bold),
							),
							SizedBox(height: 8),
							Text('• 얼굴 방향을 감지하여 중심점을 자동으로 이동시킵니다'),
							Text('• 모든 처리는 기기 내부에서만 이루어집니다'),
							Text('• 카메라 데이터는 저장되지 않습니다'),
							SizedBox(height: 16),
							Text(
								'⚡ 성능 최적화',
								style: TextStyle(fontWeight: FontWeight.bold),
							),
							SizedBox(height: 8),
							Text('• 배터리 상태에 따라 자동으로 성능을 조절합니다'),
							Text('• 저전력 모드에서는 ML 처리 빈도를 줄입니다'),
							Text('• 앱이 백그라운드로 이동하면 자동으로 최적화됩니다'),
							SizedBox(height: 16),
							Text(
								'⚠️ 주의사항',
								style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange),
							),
							SizedBox(height: 8),
							Text('• 이 앱은 앱 내부에서만 동작합니다'),
							Text('• 다른 앱의 화면을 보호할 수 없습니다'),
							Text('• 완벽한 프라이버시 보호를 위해서는 물리적 필름을 사용하세요'),
						],
					),
				),
				actions: [
					TextButton(
						onPressed: () => Navigator.pop(context),
						child: const Text('확인'),
					),
				],
			),
		);
	}

	InputImage? _inputImageFromCameraImage(CameraImage image) {
		final camera = _cameras!.first;
		final sensorOrientation = camera.sensorOrientation;
		final format = InputImageFormatValue.fromRawValue(image.format.raw);
		if (format == null) return null;
		final size = Size(image.width.toDouble(), image.height.toDouble());
		final imageRotation = InputImageRotationValue.fromRawValue(sensorOrientation);
		if (imageRotation == null) return null;
		final plane = image.planes.first;
		final bytes = plane.bytes;
		return InputImage.fromBytes(
			bytes: bytes,
			metadata: InputImageMetadata(
				size: size,
				rotation: imageRotation,
				format: format,
				bytesPerRow: plane.bytesPerRow,
			),
		);
	}

	void _updateFocusFromFace(Face face) {
		final faceCenter = face.boundingBox.center;
		final screenSize = MediaQuery.of(context).size;
		final screenX = faceCenter.dx * screenSize.width / 640;
		final screenY = faceCenter.dy * screenSize.height / 480;
		final target = Offset(screenX, screenY);
		// 저전력 시 더 큰 감쇠로 움직임 완화
		final lerpFactor = _lowPower ? 0.06 : 0.12;
		if (mounted) {
			setState(() {
				_focusCenter = Offset.lerp(_focusCenter, target, lerpFactor) ?? target;
			});
		}
	}

	Future<void> _loadShader() async {
		try {
			final program = await FragmentProgram.fromAsset('shaders/foveation.frag');
			setState(() => _program = program);
		} catch (_) {
			setState(() => _shaderEnabled = false);
		}
	}

	Shader _buildShader(Size size, Offset center) {
		final shader = _program!.fragmentShader();
		// Web 호환: 한 개씩 순서대로 setFloat 호출
		shader.setFloat(0, size.width);
		shader.setFloat(1, size.height);
		shader.setFloat(2, center.dx);
		shader.setFloat(3, center.dy);
		shader.setFloat(4, _focusRadius);
		shader.setFloat(5, _focusRadius * 0.9);
		shader.setFloat(6, _grain.clamp(0.0, 1.0));
		shader.setFloat(7, _patternType.clamp(0.0, 3.0));
		return shader;
	}

	@override
	Widget build(BuildContext context) {
		return Scaffold(
			appBar: AppBar(
				title: const Text('Privacy Mode (Prototype)'),
				actions: [
					IconButton(
						tooltip: '안내',
						icon: const Icon(Icons.info_outline),
						onPressed: () => _showPrivacyInfo(context),
					),
					IconButton(
						tooltip: '카메라',
						icon: Icon(_cameraEnabled ? Icons.camera_alt : Icons.camera_alt_outlined),
						onPressed: _cameraEnabled ? null : _requestCameraPermission,
					),
					IconButton(
						tooltip: '개인정보 안내',
						icon: const Icon(Icons.info_outline),
						onPressed: () => _showPrivacyInfo(context),
					),
					IconButton(
						tooltip: '설정',
						icon: const Icon(Icons.tune),
						onPressed: () async {
							await showModalBottomSheet(
								context: context,
								showDragHandle: true,
								builder: (_) => _SettingsSheet(
									radius: _focusRadius,
									blurSigma: _blurSigma,
									grain: _grain,
									shaderEnabled: _shaderEnabled,
									cameraEnabled: _cameraEnabled,
									patternType: _patternType,
									lowPower: _lowPower,
									mlMinIntervalMs: _mlMinIntervalMs,
									onChanged: (r, b, g, se, ce, pt, lp, ml) => setState(() {
										_focusRadius = r;
										_blurSigma = b;
										_grain = g;
										_shaderEnabled = se;
										_cameraEnabled = ce;
										_patternType = pt;
										_lowPower = lp;
										_mlMinIntervalMs = ml;
									}),
								),
							);
						},
					),
					Switch(
						value: _privacyEnabled,
						onChanged: (v) => setState(() => _privacyEnabled = v),
					),
				],
			),
			body: LayoutBuilder(
				builder: (context, constraints) {
					final size = Size(constraints.maxWidth, constraints.maxHeight);
					final center = _focusCenter == Offset.zero
						? Offset(size.width / 2, size.height / 2)
						: _focusCenter;

					return GestureDetector(
						onTapDown: (d) => setState(() => _focusCenter = d.localPosition),
						child: Stack(
							fit: StackFit.expand,
							children: [
								DecoratedBox(
									decoration: const BoxDecoration(
										gradient: LinearGradient(
											colors: [Color(0xFFF8FAFC), Color(0xFFEFF3FA)],
											stops: [0.0, 1.0],
											begin: Alignment.topLeft,
											end: Alignment.bottomRight,
										),
									),
									child: ListView.separated(
										padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
										itemCount: 24,
										separatorBuilder: (_, __) => const SizedBox(height: 12),
										itemBuilder: (_, i) => _InfoCard(index: i),
									),
								),

								if (_privacyEnabled)
									Positioned.fill(
										child: Stack(children: [
											ClipPath(
												clipper: _OutsideCircleClipper(center: center, radius: _focusRadius),
												child: BackdropFilter(
													filter: ImageFilter.blur(sigmaX: _blurSigma, sigmaY: _blurSigma),
													child: Container(color: Colors.transparent),
												),
											),
											if (_shaderEnabled && _program != null)
												CustomPaint(
													painter: _ShaderOverlayPainter(
														shaderBuilder: () => _buildShader(size, center),
													),
												),
											if (!_shaderEnabled || _program == null)
												CustomPaint(
													painter: _VignettePainter(center: center, radius: _focusRadius),
												),
											Positioned(
												right: 16,
												bottom: 16,
												child: AnimatedScale(
													duration: const Duration(milliseconds: 200),
													scale: _privacyEnabled ? 1 : 0.9,
													child: Chip(
														avatar: const Icon(Icons.visibility_off, size: 18),
														label: const Text('Privacy ON'),
														backgroundColor: Theme.of(context).colorScheme.primaryContainer,
													),
												),
											),
											if (_cameraEnabled)
												Positioned(
													left: 16,
													bottom: 16,
													child: AnimatedScale(
														duration: const Duration(milliseconds: 200),
														scale: _cameraEnabled ? 1 : 0.9,
														child: Chip(
															avatar: Icon(
																_isProcessingFrame ? Icons.face : Icons.face_outlined,
																size: 18,
															),
															label: Text(_isProcessingFrame ? 'Face Detected' : 'Face Tracking'),
															backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
														),
													),
												),
											// 배터리 상태 표시
											Positioned(
												left: 16,
												top: 16,
												child: AnimatedScale(
													duration: const Duration(milliseconds: 200),
													scale: _lowPower ? 1 : 0.9,
													child: Chip(
														avatar: Icon(
															_batteryState == BatteryState.charging 
																? Icons.battery_charging_full
																: _batteryLevel < 20 
																	? Icons.battery_alert
																	: Icons.battery_std,
															size: 18,
														),
														label: Text('${_batteryLevel}% ${_lowPower ? '(저전력)' : ''}'),
														backgroundColor: _batteryLevel < 20 
															? Colors.red.withOpacity(0.2)
															: Theme.of(context).colorScheme.tertiaryContainer,
													),
												),
											),
									]),
								),
							],
						),
					);
				},
			),
			bottomNavigationBar: _PrivacyHintBar(enabled: _privacyEnabled),
		);
	}

	void _showPrivacyInfo() {
		showModalBottomSheet(
			context: context,
			showDragHandle: true,
			builder: (context) {
				return Padding(
					padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
					child: Column(
						mainAxisSize: MainAxisSize.min,
						crossAxisAlignment: CrossAxisAlignment.start,
						children: const [
							Text('프라이버시 안내', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
							SizedBox(height: 8),
							Text('• 카메라 영상과 얼굴 데이터는 기기 내에서만 처리되며 저장/전송되지 않습니다.'),
							Text('• 프라이버시 모드는 앱 내부에서만 적용됩니다.'),
							Text('• 저전력 모드를 켜면 배터리 소모를 줄이는 대신 감지 빈도가 낮아집니다.'),
						],
					),
				);
			},
		);
	}
}

class _InfoCard extends StatelessWidget {
	const _InfoCard({required this.index});
	final int index;

	@override
	Widget build(BuildContext context) {
		final cs = Theme.of(context).colorScheme;
		return Card(
			clipBehavior: Clip.antiAlias,
			child: Column(
				children: [
					ListTile(
						leading: CircleAvatar(
							backgroundColor: cs.primaryContainer,
							child: Text('${index + 1}', style: TextStyle(color: cs.onPrimaryContainer)),
						),
						title: Text('민감 데이터 ${index + 1}'),
						subtitle: const Text('화면을 탭하면 중심이 이동합니다.'),
						trailing: const Icon(Icons.chevron_right),
					),
					const Divider(height: 1),
					Padding(
						padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
						child: Row(
							children: [
								Expanded(
									child: PrivacyMask(
										child: Text(
											'금액 • ****-****-****-1234',
											style: Theme.of(context).textTheme.bodySmall,
										),
									),
								),
								FilledButton.tonal(
									onPressed: () {},
									child: const Text('자세히'),
								),
							],
						),
					),
				],
			),
		);
	}
}

class _OutsideCircleClipper extends CustomClipper<Path> {
	_OutsideCircleClipper({required this.center, required this.radius});
	final Offset center;
	final double radius;

	@override
	Path getClip(Size size) {
		final rect = Offset.zero & size;
		final outer = Path()..addRect(rect);
		final inner = Path()..addOval(Rect.fromCircle(center: center, radius: radius));
		return Path.combine(PathOperation.difference, outer, inner);
	}

	@override
	bool shouldReclip(covariant _OutsideCircleClipper oldClipper) {
		return oldClipper.center != center || oldClipper.radius != radius;
	}
}

class _VignettePainter extends CustomPainter {
	_VignettePainter({required this.center, required this.radius});
	final Offset center;
	final double radius;

	@override
	void paint(Canvas canvas, Size size) {
		final rect = Offset.zero & size;
		final shader = RadialGradient(
			colors: [
				Colors.transparent,
				Colors.black.withOpacity(0.06),
				Colors.black.withOpacity(0.16),
				Colors.black.withOpacity(0.28),
			],
			stops: const [0.0, 0.9, 1.1, 1.35],
			center: Alignment(center.dx / size.width * 2 - 1, center.dy / size.height * 2 - 1),
			radius: (radius / (size.shortestSide / 2)).clamp(0.1, 2.0),
		).createShader(rect);

		final paint = Paint()..shader = shader;
		canvas.drawRect(rect, paint);
	}

	@override
	bool shouldRepaint(covariant _VignettePainter oldDelegate) {
		return oldDelegate.center != center || oldDelegate.radius != radius;
	}
}

class _ShaderOverlayPainter extends CustomPainter {
	_ShaderOverlayPainter({required this.shaderBuilder});
	final Shader Function() shaderBuilder;

	@override
	void paint(Canvas canvas, Size size) {
		final paint = Paint()..shader = shaderBuilder();
		canvas.drawRect(Offset.zero & size, paint);
	}

	@override
	bool shouldRepaint(covariant _ShaderOverlayPainter oldDelegate) {
		return true;
	}
}

class _SettingsSheet extends StatefulWidget {
	const _SettingsSheet({required this.radius, required this.blurSigma, required this.grain, required this.shaderEnabled, required this.cameraEnabled, required this.patternType, required this.lowPower, required this.mlMinIntervalMs, required this.onChanged});
	final double radius;
	final double blurSigma;
	final double grain;
	final bool shaderEnabled;
	final bool cameraEnabled;
	final double patternType;
	final bool lowPower;
	final int mlMinIntervalMs;
	final void Function(double radius, double blurSigma, double grain, bool shaderEnabled, bool cameraEnabled, double patternType, bool lowPower, int mlMinIntervalMs) onChanged;

	@override
	State<_SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<_SettingsSheet> {
	late double _r = widget.radius;
	late double _b = widget.blurSigma;
	late double _g = widget.grain;
	late bool _se = widget.shaderEnabled;
	late bool _ce = widget.cameraEnabled;
	late double _pt = widget.patternType;
	late bool _lp = widget.lowPower;
	late double _ml = widget.mlMinIntervalMs.toDouble();

	@override
	Widget build(BuildContext context) {
		return Padding(
			padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
			child: Column(
				mainAxisSize: MainAxisSize.min,
				crossAxisAlignment: CrossAxisAlignment.start,
				children: [
					Row(
						children: [
							const Icon(Icons.remove_red_eye_outlined),
							const SizedBox(width: 8),
							Text('프라이버시 설정', style: Theme.of(context).textTheme.titleMedium),
						],
					),
					const SizedBox(height: 16),
					SwitchListTile(
						title: const Text('쉐이더 감쇠 사용'),
						subtitle: const Text('디바이스 미지원 시 자동 비활성화'),
						value: _se,
						onChanged: (v) => setState(() => _se = v),
					),
					SwitchListTile(
						title: const Text('카메라 시선 추정'),
						subtitle: const Text('얼굴 방향으로 중심 자동 이동'),
						value: _ce,
						onChanged: (v) => setState(() => _ce = v),
					),
					SwitchListTile(
						title: const Text('저전력 모드'),
						subtitle: const Text('감지 빈도 낮추고 움직임 스무딩 강화'),
						value: _lp,
						onChanged: (v) => setState(() => _lp = v),
					),
					const SizedBox(height: 8),
					Text('중심 반경: ${_r.toStringAsFixed(0)} px'),
					Slider(
						value: _r,
						min: 80,
						max: 260,
						divisions: 18,
						onChanged: (v) => setState(() => _r = v),
					),
					Text('블러 강도: ${_b.toStringAsFixed(0)}'),
					Slider(
						value: _b,
						min: 2,
						max: 18,
						divisions: 16,
						onChanged: (v) => setState(() => _b = v),
					),
					Text('그레인 강도: ${_g.toStringAsFixed(2)}'),
					Slider(
						value: _g,
						min: 0.0,
						max: 0.5,
						divisions: 20,
						onChanged: (v) => setState(() => _g = v),
					),
					Text('패턴 타입: ${_getPatternName(_pt)}'),
					Slider(
						value: _pt,
						min: 0.0,
						max: 3.0,
						divisions: 3,
						onChanged: (v) => setState(() => _pt = v),
					),
					Text('감지 최소 간격: ${_ml.toStringAsFixed(0)} ms'),
					Slider(
						value: _ml,
						min: 60,
						max: 240,
						divisions: 12,
						onChanged: (v) => setState(() => _ml = v),
					),
					const SizedBox(height: 4),
					Row(
						children: [
							Expanded(
								child: OutlinedButton(
									onPressed: () => Navigator.pop(context),
									child: const Text('취소'),
								),
							),
							const SizedBox(width: 12),
							Expanded(
								child: FilledButton(
									onPressed: () {
										widget.onChanged(_r, _b, _g, _se, _ce, _pt, _lp, _ml.round());
										Navigator.pop(context);
									},
									child: const Text('적용'),
								),
							),
						],
					),
				],
			),
		);
	}

	String _getPatternName(double patternType) {
		switch (patternType.round()) {
			case 0: return '노이즈';
			case 1: return '해칭';
			case 2: return '도트';
			case 3: return '웨이브';
			default: return '노이즈';
		}
	}
}

class _PrivacyHintBar extends StatelessWidget {
	const _PrivacyHintBar({required this.enabled});
	final bool enabled;

	@override
	Widget build(BuildContext context) {
		return AnimatedContainer(
			duration: const Duration(milliseconds: 250),
			height: 48,
			padding: const EdgeInsets.symmetric(horizontal: 16),
			decoration: BoxDecoration(
				color: enabled
					? Theme.of(context).colorScheme.primaryContainer
					: Theme.of(context).colorScheme.surface,
				border: Border(
					top: BorderSide(color: Theme.of(context).dividerColor),
				),
			),
			child: Row(
				children: [
					Icon(
						enabled ? Icons.lock_outline : Icons.lock_open_outlined,
						color: Theme.of(context).colorScheme.onPrimaryContainer,
					),
					const SizedBox(width: 12),
					Expanded(
						child: Text(
							enabled ? '프라이버시 모드: 주변 흐림/감쇠 적용 중' : '프라이버시 모드 꺼짐',
							style: Theme.of(context).textTheme.bodyMedium,
						),
					),
				],
			),
		);
	}
}

// 민감 영역 마스킹 위젯
class PrivacyMask extends StatefulWidget {
	const PrivacyMask({
		super.key,
		required this.child,
		this.maskType = PrivacyMaskType.blur,
		this.intensity = 1.0,
		this.autoDetect = true,
	});

	final Widget child;
	final PrivacyMaskType maskType;
	final double intensity;
	final bool autoDetect;

	@override
	State<PrivacyMask> createState() => _PrivacyMaskState();
}

class _PrivacyMaskState extends State<PrivacyMask> {
	bool _isInFocus = false;
	Offset? _focusCenter;
	double? _focusRadius;

	@override
	Widget build(BuildContext context) {
		return Consumer<PrivacyState>(
			builder: (context, privacyState, child) {
				final isPrivacyEnabled = privacyState.isEnabled;
				
				if (!isPrivacyEnabled || _isInFocus) {
					return widget.child;
				}

				return _buildMaskedWidget();
			},
		);
	}

	Widget _buildMaskedWidget() {
		switch (widget.maskType) {
			case PrivacyMaskType.blur:
				return ClipRRect(
					borderRadius: BorderRadius.circular(8),
					child: BackdropFilter(
						filter: ImageFilter.blur(
							sigmaX: 8.0 * widget.intensity,
							sigmaY: 8.0 * widget.intensity,
						),
						child: Container(
							color: Colors.white.withOpacity(0.1),
							child: widget.child,
						),
					),
				);
			case PrivacyMaskType.pixelate:
				return _PixelatedWidget(
					intensity: widget.intensity,
					child: widget.child,
				);
			case PrivacyMaskType.overlay:
				return Stack(
					children: [
						widget.child,
						Container(
							decoration: BoxDecoration(
								color: Colors.black.withOpacity(0.7 * widget.intensity),
								borderRadius: BorderRadius.circular(8),
							),
							child: Center(
								child: Icon(
									Icons.visibility_off,
									color: Colors.white.withOpacity(0.8),
								),
							),
						),
					],
				);
		}
	}
}

enum PrivacyMaskType { blur, pixelate, overlay }

// 픽셀화 효과 위젯
class _PixelatedWidget extends StatelessWidget {
	const _PixelatedWidget({required this.intensity, required this.child});
	final double intensity;
	final Widget child;

	@override
	Widget build(BuildContext context) {
		return CustomPaint(
			painter: _PixelatePainter(intensity: intensity),
			child: child,
		);
	}
}

class _PixelatePainter extends CustomPainter {
	_PixelatePainter({required this.intensity});
	final double intensity;

	@override
	void paint(Canvas canvas, Size size) {
		final paint = Paint()
			..color = Colors.black.withOpacity(0.3 * intensity)
			..style = PaintingStyle.fill;

		final pixelSize = 8.0 * intensity;
		for (double x = 0; x < size.width; x += pixelSize) {
			for (double y = 0; y < size.height; y += pixelSize) {
				canvas.drawRect(
					Rect.fromLTWH(x, y, pixelSize, pixelSize),
					paint,
				);
			}
		}
	}

	@override
	bool shouldRepaint(covariant _PixelatePainter oldDelegate) {
		return oldDelegate.intensity != intensity;
	}
}

// 프라이버시 상태 관리
class PrivacyState extends ChangeNotifier {
	bool _isEnabled = false;
	Offset _focusCenter = Offset.zero;
	double _focusRadius = 140;

	bool get isEnabled => _isEnabled;
	Offset get focusCenter => _focusCenter;
	double get focusRadius => _focusRadius;

	void setEnabled(bool enabled) {
		_isEnabled = enabled;
		notifyListeners();
	}

	void setFocus(Offset center, double radius) {
		_focusCenter = center;
		_focusRadius = radius;
		notifyListeners();
	}
}

// Consumer 위젯 (간단한 상태 관리)
class Consumer<T extends ChangeNotifier> extends StatefulWidget {
	const Consumer({super.key, required this.builder});
	final Widget Function(BuildContext context, T value, Widget? child) builder;

	@override
	State<Consumer<T>> createState() => _ConsumerState<T>();
}

class _ConsumerState<T extends ChangeNotifier> extends State<Consumer<T>> {
	late T _value;

	@override
	void initState() {
		super.initState();
		// 실제 구현에서는 Provider나 다른 상태 관리 솔루션 사용
		_value = PrivacyState() as T;
		_value.addListener(_onChange);
	}

	@override
	void dispose() {
		_value.removeListener(_onChange);
		super.dispose();
	}

	void _onChange() {
		setState(() {});
	}

	@override
	Widget build(BuildContext context) {
		return widget.builder(context, _value, null);
	}
}
