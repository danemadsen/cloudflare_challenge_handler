A flutter package to handle cloudflare challenges using webview and dio

## Features

The handler widget will automatically open a webview for cloudflare when a challenge is detected.

## Getting started

To use the package, add `cloudflare_challenge_handler` to your `pubspec.yaml` file.

```yaml
dependencies:
  cloudflare_challenge_handler: ^1.0.0
```

Then import the package to your dart file.

```dart
import 'package:cloudflare_challenge_handler/cloudflare_challenge_handler.dart';
```

## Usage

The package provides a `CloudflareChallengeHandler` widget that will handle the cloudflare challenge.
The widget should be added as a parent of any area of ui code where you intend on using a cloudflare protected api / website.
Ensure you use the same dio and cookie jar instance for the handler and the api / website.

```dart
CloudflareChallengeHandler(
  dio: dio,
  cookieJar: cookieJar,
  child: Scaffold(
    appBar: AppBar(
      title: Text('Cloudflare Challenge Handler Example'),
    ),
    body: Center(
      child: ElevatedButton(
        onPressed: () async {
          final response = await dio.get('https://example.com');
          print(response.data);
        },
        child: Text('Get Data'),
      ),
    ),
  ),
)
```

