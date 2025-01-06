import 'dart:async';
import 'dart:io' as io;

import 'package:cloudflare_interceptor/src/request_options_extension.dart';
import 'package:cloudflare_interceptor/src/response_extension.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:html/parser.dart';

/// An interceptor for handling Cloudflare challenges in Dio requests.
/// 
/// This interceptor detects Cloudflare challenges in responses and errors,
/// and attempts to solve them using a WebView. If the challenge is solved,
/// it retries the request with the solved data.
/// 
/// The interceptor requires a [Dio] instance, a [CookieJar] for storing cookies,
/// and a [BuildContext] for displaying a WebView dialog if necessary.
/// 
/// Example usage:
/// ```dart
/// final dio = Dio();
/// final cookieJar = CookieJar();
/// final context = ...; // Obtain a BuildContext
/// 
/// dio.interceptors.add(CloudflareInterceptor(
///   dio: dio,
///   cookieJar: cookieJar,
///   context: context,
/// ));
/// ```
/// 
/// The interceptor overrides the [onResponse] and [onError] methods to handle
/// Cloudflare challenges. If a challenge is detected, it calls [solveCloudflare]
/// to solve the challenge using a WebView.
/// 
/// The [solveCloudflare] method initializes a headless WebView to solve the challenge.
/// If the challenge is not solved within 5 seconds, it displays a fullscreen dialog
/// with the WebView to allow the user to solve the challenge manually.
/// 
/// The [onLoadStop] method is called when the WebView finishes loading a page.
/// It checks if the challenge is solved by examining the page title and cookies.
/// If the challenge is solved, it completes the [_completer] with the solved data
/// and dismisses the dialog if it was displayed.
class CloudflareInterceptor extends Interceptor {
  /// An instance of the Dio HTTP client used to make network requests.
  final Dio dio;

  /// A `CookieJar` instance used to manage cookies for HTTP requests and responses.
  final CookieJar cookieJar;

  /// The [BuildContext] associated with this interceptor.
  /// This context is used to access the widget tree and other context-specific information.
  final BuildContext context;

  Completer<String?> _completer = Completer<String?>.sync();
  bool _usingDialog = false;

  /// Interceptor for handling Cloudflare challenges.
  ///
  /// This interceptor is responsible for managing the interaction with Cloudflare's
  /// challenge pages, ensuring that requests can be made successfully.
  ///
  /// Parameters:
  /// - `dio`: The Dio instance used for making HTTP requests.
  /// - `cookieJar`: The CookieJar instance used for managing cookies.
  /// - `context`: The BuildContext instance used for accessing the widget tree.
  CloudflareInterceptor({
    required this.dio, 
    required this.cookieJar, 
    required this.context
  });

  /// Intercepts the response to check if it is a Cloudflare challenge.
  /// 
  /// If the response is identified as a Cloudflare challenge, it attempts to solve the challenge using a WebView.
  /// Upon solving the challenge, it creates a new response with the solved data and passes it to the next handler.
  /// If an error occurs while solving the challenge, it rejects the response with the error.
  /// 
  /// If the response is not a Cloudflare challenge, it proceeds as normal.
  /// 
  /// @param response The intercepted response.
  /// @param handler The handler to pass the response to the next interceptor or to reject it.
  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) async {
    if (await response.isCloudflareChallenge) {
      // Solve challenge using a WebView
      try {
        _solveCloudflare(response.requestOptions);
        final solvedData = await _completer.future;
        if (solvedData != null) {
          final newResponse = Response(
            requestOptions: response.requestOptions,
            data: solvedData,
            statusCode: 200,
            extra: {'cloudflare': true},
          );
          handler.next(newResponse);
        }
      } catch (e) {
        handler.reject(DioException(requestOptions: response.requestOptions, error: e));
      }
    }
    else {
      // If not a Cloudflare challenge, proceed as normal
      handler.next(response);
    }
  }

  /// Intercepts errors and checks if the error response is a Cloudflare challenge.
  /// If it is, attempts to solve the challenge and retry the request with the solved data.
  /// 
  /// If the challenge is solved successfully, a new response with the solved data is created
  /// and the handler resolves it. If an error occurs during the solving process, the handler
  /// rejects the error.
  /// 
  /// If the error is not a Cloudflare challenge, the error is passed to the next handler.
  /// 
  /// - Parameters:
  ///   - err: The error that occurred during the request.
  ///   - handler: The error interceptor handler to manage the error.
  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    if (err.response != null && await err.response!.isCloudflareChallenge) {
      try {
        _solveCloudflare(err.requestOptions);
        final solvedData = await _completer.future;
        if (solvedData != null) {
          final newResponse = Response(
            requestOptions: err.requestOptions,
            data: solvedData,
            statusCode: 200,
            extra: {'cloudflare': true},
          );
          handler.resolve(newResponse);
        }
      } catch (e) {
        handler.reject(DioException(requestOptions: err.requestOptions, error: e));
      }
    }
    else {
      // If not a Cloudflare challenge, proceed as normal
      handler.next(err);
    }
  }

  void _solveCloudflare(RequestOptions requestOptions) async {
    _completer = Completer();

    final initialSettings = requestOptions.getWebViewSettings();

    final initialUrlRequest = await requestOptions.getURLRequest();

    final headlessWebView = HeadlessInAppWebView(
			initialSettings: initialSettings,
			initialUrlRequest: initialUrlRequest,
			onLoadStop: _onLoadStop,
		);

    await headlessWebView.run();

    await Future.any([
			_completer.future,
			Future.delayed(const Duration(seconds: 5))
		]);

    if (_completer.isCompleted) {
      headlessWebView.dispose();
      return;
    }

    if (!context.mounted) throw Exception('Context is not mounted');

    showDialog(
      context: context, 
      builder: (context) => Dialog.fullscreen(
        child: InAppWebView(
		  		headlessWebView: headlessWebView,
		  		initialSettings: initialSettings,
		  		initialUrlRequest: initialUrlRequest,
		  		onLoadStop: _onLoadStop,
		  	)
      )
    );

    _usingDialog = true;
  }

  void _onLoadStop(InAppWebViewController controller, WebUri? uri) async {
    final html = await controller.getHtml();
    if (html == null) return;

    final doc = parse(html);
    final title = doc.querySelector('title')?.text.toLowerCase() ?? '';

    // If the title no longer matches challenge keywords, we consider it solved.
    if (
      title.contains('cloudflare') ||
      title.contains('just a moment') ||
      title.contains('verification required')
    ) return;
    
    // Get cookies from the WebView (InAppWebViewCookie)
    final inAppCookies = await CookieManager.instance().getCookies(url: uri!);

    // Convert InAppWebViewCookie to dart:io Cookie
    final ioCookies = inAppCookies.map((c) {
      final cookie = io.Cookie(c.name, c.value);
      cookie.domain = c.domain;
      cookie.path = c.path ?? '/';
      if (c.expiresDate != null) {
        cookie.expires = DateTime.fromMillisecondsSinceEpoch(c.expiresDate!);
      }
      cookie.secure = c.isSecure ?? false;
      cookie.httpOnly = c.isHttpOnly ?? false;
      return cookie;
    }).toList();

    // Store the converted cookies in the Dio cookie jar
    cookieJar.saveFromResponse(uri, ioCookies);

    // Complete the challenge
    _completer.complete(html);

    // Dismiss the dialog
    if (_usingDialog) {
      if (!context.mounted) throw Exception('Context is not mounted');
      
      Navigator.of(context).pop();

      _usingDialog = false;
    }
  }
}