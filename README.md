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

<hr/>

## 환경 설정 단계별 가이드
### A. Flutter SDK 설치
```PowerShell
# 1. Flutter SDK 다운로드
# https://docs.flutter.dev/get-started/install

# 2. 환경변수 설정 (Windows)
setx PATH "$PATH$;C:\flutter\bin"

# 3. 설치 확인
flutter doctor
```

### B. 개발 도구 설치
```PowerShell
# Android Studio (Android 개발용)
# https://developer.android.com/studio

# Xcode (iOS 개발용, macOS만)
# App Store에서 설치
```

### C. 프로젝트 실행
```PowerShell
# 1. 프로젝트 폴더로 이동
cd "폴더 경로"

# 2. 의존성 설치
flutter pub get

# 3. 실행
flutter run
```

## ✅ 플랫폼 별 추가 설정
### Android 실행
```PowerShell
# Android 에뮬레이터 또는 실제 기기 연결 후
flutter run -d android
```

### iOS 실행 (macOS만)
```PowerShell
# iOS 시뮬레이터 또는 실제 기기 연결 후
flutter run -d ios
```

<hr/>

## 배포 방안 비교
### 방안 1: 소스코드 배포 (현재 상태)
* 장점
+ 즉시 실행 가능
+ 코드 수정 가능
+ 학습 목적에 적합
* 단점
+ Flutter 환경 설정 필요
+ 개발 도구 설치 필요
+ 기술적 지식 필요
### 적합한 경우:
* 개발자/학습자
* 코드 수정이 필요한 경우
* 기술적 검토가 필요한 경우
### 방안 2: APK/IPA 빌드 배포
* 장점
+ 설치만 하면 바로 실행
+ Flutter 환경 불필요
+ 일반 사용자도 사용 가능
* 단점
+ 플랫폼별로 별도 빌드 필요
+ 코드 수정 불가
+ 앱 서명 필요
### 빌드 방법:
```PowerShell
# Android APK 빌드
flutter build apk --release

# iOS IPA 빌드 (macOS만)
flutter build ios --release
```

### 방안 3: 웹 버전 배포
* 장점
+ 브라우저에서 바로 실행
+ 플랫폼 무관
+ 배포가 간단
* 단점
+ 카메라 기능 제한
+ 성능 제한
+ 일부 기능 미지원
### 빌드 방법:
```PowerShell
flutter build web
```

### 방안 4: 앱 스토어 배포
* 장점
+ 공식 배포
+ 자동 업데이트
+ 신뢰성 높음
* 단점
+ 심사 과정 필요
+ 개발자 계정 필요
+ 시간 소요

## 추천 방안
### 즉시 테스트용: 방안 1 (소스코드)
```PowerShell
# 1. 필수 파일 4개 복사
# 2. Flutter SDK 설치
flutter pub get
flutter run
```
### 일반 사용자용: 방안 2 (APK/IPA)
```PowerShell
# Android용
flutter build apk --release
# 생성된 파일: build/app/outputs/fluuter-apk/app-release.apk
```
### 데모/프레젠테이션용: 방안 3 (웹)
```PowerShell
flutter build web
# 생성된 파일: build/web/ 폴더 전체
```

## 새 환경에서의 실행 체크리스트
### 필수 확인사항:
* [ ] Flutter SDK 설치됨
* [ ] flutter doctor 통과
* [ ] Android Studio 또는 Xcode 설치됨
* [ ] 에뮬레이터 또는 실제 기기 연결됨
* [ ] 프로젝트 파일 4개 복사됨

### 권한 설정:
```PowerShell
<!-- android/app/src/main/AndroidManifest.xml -->
<uses-permission android:name="android.permission.CAMERA" />
<uses-permission android:name="android.permission.INTERNET" />
```

### 실행 명령어:
```PowerShell
# 의존성 설치
flutter pub get

# 실행
flutter run

# 특정 기기에서 실행
flutter devices
flutter run -d [device-id]
```

## 문제 해결
### 자주 발생하는 문제:
1. 카메라 권한 거부: 앱 설정에서 권한 허용
2. 의존성 오류: flutter clean && flutter pub get
3. 빌드 실패: flutter doctor로 환경 확인
4. 기기 인식 안됨: USB 디버깅 활성화

### 디버깅 명령어:
```PowerShell
# 환경 확인
flutter doctor -v

# 의존성 확인
flutter pub deps

# 빌드 로그 확인
flutter run --verbose
```

## 최종 추천
* 학습/개발 목적: 소스코드 배포 (방안 1)
* 일반 사용자: APK 빌드 배포 (방안 2)
* 데모/프레젠테이션: 웹 버전 (방안 3)