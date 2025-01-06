A flutter package to handle cloudflare challenges using webview and dio

## Features

The handler widget will automatically open a webview for cloudflare when a challenge is detected.

## Getting started

To use the package, add `cloudflare_interceptor` to your `pubspec.yaml` file.

```yaml
dependencies:
  cloudflare_interceptor: ^0.0.3
```

Then import the package to your dart file.

```dart
import 'package:cloudflare_interceptor/cloudflare_interceptor.dart';
```

## Usage

The package provides a `CloudflareInterceptor` class that can be used as an interceptor in `dio` to handle cloudflare challenges.

```dart
dio.interceptors.add(CloudflareInterceptor(
  dio: dio, 
  cookieJar: cookieJar, 
  context: context
));
```

