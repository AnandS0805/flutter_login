import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'services/token_service.dart';
import 'services/api_client.dart';

import 'login_page.dart';
import 'attendance/attendance_page.dart';
import 'attendance/attendance_theme.dart';

class AuthCheckPage extends StatefulWidget {
  const AuthCheckPage({super.key});

  @override
  State<AuthCheckPage> createState() => _AuthCheckPageState();
}

class _AuthCheckPageState extends State<AuthCheckPage> {
  // Current screen loading state
  bool isLoading = true;

  // Error screen ke title aur message
  String? errorTitle;
  String? errorMessage;

  @override
  void initState() {
    super.initState();

    checkToken(); // App open hone par authentication check
  }

  // ================= CHECK TOKEN =================

  Future<void> checkToken() async {
    // Loading start aur previous error clear
    setState(() {
      isLoading = true;
      errorTitle = null;
      errorMessage = null;
    });

    try {
      final tokenService = TokenService();

      // Saved Access Token get karo
      final token = await tokenService.getToken();

      if (!mounted) return;

      // Token nahi mila toh Login Page
      if (token == null || token.isEmpty) {
        debugPrint('Token Not Found');

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const LoginPage()),
        );

        return;
      }

      debugPrint('Token Found');

      // ApiClient automatically Access Token attach karega
      // Expired token hone par Refresh API call karega
      final apiClient = ApiClient();

      final response = await apiClient.get('/profile');

      debugPrint('Profile Status: ${response.statusCode}');
      debugPrint('Profile Data: ${response.body}');

      if (!mounted) return;

      // ================= SUCCESS =================

      if (response.statusCode == 200) {
        final profile = jsonDecode(response.body);

        final user = profile['user'];

        final name = user['name'];
        final email = user['email'];
        final mobile = user['mobile'];

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) =>
                AttendancePage(userName: name, email: email, mobile: mobile),
          ),
        );
      }
      // ================= UNAUTHORIZED =================
      else if (response.statusCode == 401) {
        await tokenService.deleteAllTokens();

        if (!mounted) return;

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const LoginPage()),
        );
      }
      // ================= SERVER ERROR =================
      else if (response.statusCode >= 500) {
        showError(
          'Server Unavailable',
          'Our server is temporarily unavailable. Please try again later.',
        );
      }
      // ================= OTHER ERRORS =================
      else {
        showError(
          'Something Went Wrong',
          'We could not load your profile. Please try again.',
        );
      }
    }
    // ================= TIMEOUT ERROR =================
    on TimeoutException {
      showError(
        'Request Timeout',
        'The server is taking too long to respond. Please try again.',
      );
    }
    // ================= INTERNET ERROR =================
    on SocketException {
      showError(
        'No Internet Connection',
        'Please check your internet connection and try again.',
      );
    }
    // ================= HTTP CLIENT ERROR =================
    on http.ClientException {
      showError(
        'Connection Failed',
        'Unable to connect to the server. Please check your connection.',
      );
    }
    // ================= INVALID RESPONSE =================
    on FormatException {
      showError(
        'Invalid Server Response',
        'We received an unexpected response from the server. Please try again.',
      );
    }
    // ================= OTHER ERRORS =================
    catch (e) {
      debugPrint('Auth Check Error: $e');

      showError(
        'Something Went Wrong',
        'An unexpected error occurred. Please try again.',
      );
    }
  }

  // ================= SHOW ERROR =================

  void showError(String title, String message) {
    if (!mounted) return;

    setState(() {
      isLoading = false;
      errorTitle = title;
      errorMessage = message;
    });
  }

  // ================= SHIMMER BOX =================

  Widget _shimmerBox(double width, double height, {double radius = 8}) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.2, end: 0.8),
      duration: const Duration(milliseconds: 900),

      builder: (context, value, child) {
        return Container(
          width: width,
          height: height,

          decoration: BoxDecoration(
            color: kGreen.withValues(alpha: value * 0.15),

            borderRadius: BorderRadius.circular(radius),

            border: Border.all(color: kGreen.withValues(alpha: value * 0.35)),
          ),
        );
      },

      onEnd: () {},
    );
  }

  // ================= ERROR SCREEN =================

  Widget errorScreen() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(25),

        child: Column(
          mainAxisSize: MainAxisSize.min,

          children: [
            // Error Icon
            Icon(Icons.cloud_off_rounded, size: 65, color: kGreen),

            const SizedBox(height: 22),

            // Error Title
            Text(
              errorTitle ?? 'Something Went Wrong',

              textAlign: TextAlign.center,

              style: const TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),

            const SizedBox(height: 12),

            // Error Message
            Text(
              errorMessage ?? 'Please try again.',

              textAlign: TextAlign.center,

              style: TextStyle(
                fontSize: 14,
                height: 1.5,
                color: Colors.grey.shade600,
              ),
            ),

            const SizedBox(height: 28),

            // Retry Button
            SizedBox(
              width: 170,
              height: 48,

              child: ElevatedButton.icon(
                onPressed: checkToken,

                icon: const Icon(Icons.refresh),

                label: const Text(
                  'Retry',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),

                style: ElevatedButton.styleFrom(
                  backgroundColor: kGreen,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ================= LOADING SCREEN =================

  Widget loadingScreen() {
    return Padding(
      padding: const EdgeInsets.all(20),

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,

        children: [
          const SizedBox(height: 20),

          // Profile skeleton
          Row(
            children: [
              _shimmerBox(55, 55, radius: 50),

              const SizedBox(width: 14),

              Column(
                crossAxisAlignment: CrossAxisAlignment.start,

                children: [
                  _shimmerBox(120, 12),

                  const SizedBox(height: 10),

                  _shimmerBox(170, 16),

                  const SizedBox(height: 8),

                  _shimmerBox(130, 10),
                ],
              ),
            ],
          ),

          const SizedBox(height: 35),

          // Clock skeleton
          _shimmerBox(double.infinity, 110, radius: 12),

          const SizedBox(height: 35),

          // Punch button skeleton
          Center(child: _shimmerBox(190, 190, radius: 100)),

          const SizedBox(height: 35),

          // Bottom cards
          _shimmerBox(double.infinity, 75, radius: 12),

          const SizedBox(height: 18),

          _shimmerBox(double.infinity, 100, radius: 12),

          const Spacer(),

          Center(
            child: Text(
              'INITIALIZING SYSTEM...',
              style: mono(12, color: kGreen),
            ),
          ),

          const SizedBox(height: 15),
        ],
      ),
    );
  }

  // ================= BUILD =================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,

      body: SafeArea(child: isLoading ? loadingScreen() : errorScreen()),
    );
  }
}
