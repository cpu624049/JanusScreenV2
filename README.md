# Privacy Foveation Prototype (Flutter)

하드웨어 없이 적용 가능한 "완화형 프라이버시 모드" 프로토타입입니다.

- 앱 내부에서만 동작합니다(전역 오버레이 아님)
- 프라이버시 토글 ON 시 중심은 선명하게, 주변은 그라디언트 감쇠(초기 버전)
- 이후 단계에서 쉐이더 기반 블러/패턴/민감 영역 마스킹을 추가합니다

## 요구사항
- Flutter SDK (3.22+ 권장) 및 Dart
- Android Studio 또는 Xcode

설치 가이드는 Flutter 공식 문서 참고: https://docs.flutter.dev/get-started/install

## 설치 및 실행
```bash
flutter pub get
flutter run
```

## 파일 구조
- `pubspec.yaml`: 의존성 설정
- `lib/main.dart`: 데모 UI와 프라이버시 오버레이 골격
- `README.md`: 설명서

## 다음 단계
- 시선 추정(카메라+ML)로 중심 자동화
- 쉐이더 기반 foveation 블러/대비 저하
- 민감 영역 마스킹 위젯 API
- 고주파 패턴/노이즈 오버레이
