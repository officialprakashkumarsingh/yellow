import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ahamai/ui_widgets.dart';

class AuthService {
  static final AuthService instance = AuthService._internal();
  factory AuthService() => instance;
  AuthService._internal();

  SupabaseClient get _client => Supabase.instance.client;

  // --- START: Anti-Spam Measures ---
  final Set<String> _disposableDomains = {
    '10minutemail.com', 'temp-mail.org', 'guerrillamail.com', 'mailinator.com',
    'getnada.com', 'throwawaymail.com', 'tempmail.com', 'maildrop.cc',
    'yopmail.com', 'fakemail.net', 'dispostable.com', 'mohmal.com', 'tmail.ai',
    'tempmailo.com', 'mailpoof.com', 'mail-temp.com', 'tempinbox.com',
    'emailondeck.com', '10minutemail.net', 'tempail.com', 't.odmail.cn'
  };

  String _normalizeEmail(String email) {
    var trimmedEmail = email.trim().toLowerCase();
    if (trimmedEmail.contains('+')) {
      final parts = trimmedEmail.split('@');
      if (parts.length == 2) {
        final localPart = parts[0];
        final domain = parts[1];
        if (localPart.contains('+')) {
          final mainLocalPart = localPart.split('+')[0];
          return '$mainLocalPart@$domain';
        }
      }
    }
    return trimmedEmail;
  }
  
  // --- END: Anti-Spam Measures ---

  Future<void> initialize() async {
    await Supabase.initialize(
      url: 'https://oaoagwlcxfagzxckkxdd.supabase.co',
      anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9hb2Fnd2xjeGZhZ3p4Y2treGRkIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTQzMDgyOTQsImV4cCI6MjA2OTg4NDI5NH0.bdHmfBnCFK4taJ18Q8ZP-ItXNEnUuRhUtLT_1fsOino',
    );
  }

  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;
  User? get currentUser => _client.auth.currentUser;

  Future<AuthResponse> signUp({required String email, required String password}) async {
    final normalizedEmail = _normalizeEmail(email);
    final domain = normalizedEmail.split('@').last;
    if (_disposableDomains.contains(domain)) {
      throw const AuthException('Disposable email addresses are not allowed. Please use a permanent email.');
    }
    return await _client.auth.signUp(email: normalizedEmail, password: password);
  }

  Future<AuthResponse> signIn({required String email, required String password}) async {
    final normalizedEmail = _normalizeEmail(email);
    return await _client.auth.signInWithPassword(email: normalizedEmail, password: password);
  }

  Future<void> signOut() async {
    await _client.auth.signOut();
  }
}

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool _isLogin = true;
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;

  void _showErrorSnackBar(String message) {
    if(!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message, style: const TextStyle(color: Colors.white)),
      backgroundColor: Colors.redAccent,
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  Future<void> _handleAuth() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      if (_isLogin) {
        await AuthService.instance.signIn(email: _emailController.text, password: _passwordController.text);
      } else {
        await AuthService.instance.signUp(email: _emailController.text, password: _passwordController.text);
      }
    } on AuthException catch (e) {
      _showErrorSnackBar(e.message);
    } catch (e) {
      _showErrorSnackBar('An unexpected error occurred.');
    } finally {
      if(mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          StaticGradientBackground(isDark: isDark),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(CupertinoIcons.sparkles, size: 60),
                    const SizedBox(height: 16),
                    Text(
                      _isLogin ? 'Welcome Back' : 'Create Account',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _isLogin ? 'Sign in to continue your journey with AhamAI.' : 'Sign up to start exploring with AhamAI.',
                       textAlign: TextAlign.center,
                       style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Theme.of(context).hintColor),
                    ),
                    const SizedBox(height: 32),
                    GlassmorphismPanel(
                      child: TextFormField(
                        controller: _emailController,
                        style: const TextStyle(fontSize: 16),
                        decoration: const InputDecoration(
                          hintText: 'Email', 
                          border: InputBorder.none, 
                          prefixIcon: Icon(CupertinoIcons.mail, size: 22), 
                          contentPadding: EdgeInsets.symmetric(vertical: 18),
                        ),
                        validator: (value) => (value == null || !value.contains('@')) ? 'Please enter a valid email' : null,
                        keyboardType: TextInputType.emailAddress,
                      ),
                    ),
                    const SizedBox(height: 16),
                    GlassmorphismPanel(
                      child: TextFormField(
                        controller: _passwordController,
                        style: const TextStyle(fontSize: 16),
                        decoration: const InputDecoration(
                          hintText: 'Password', 
                          border: InputBorder.none, 
                          prefixIcon: Icon(CupertinoIcons.lock, size: 22), 
                          contentPadding: EdgeInsets.symmetric(vertical: 18),
                        ),
                        obscureText: true,
                        validator: (value) => (value == null || value.length < 6) ? 'Password must be at least 6 characters' : null,
                      ),
                    ),
                    const SizedBox(height: 24),
                    GestureDetector(
                      onTap: _isLoading ? null : _handleAuth,
                      child: GlassmorphismPanel(
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          child: Center(
                            child: _isLoading 
                            ? const CupertinoActivityIndicator() 
                            : Text(
                                _isLogin ? 'Sign In' : 'Sign Up',
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                              ),
                          ),
                        ),
                      ),
                    ),
                    CupertinoButton(
                      onPressed: () => setState(() => _isLogin = !_isLogin),
                      child: Text(
                        _isLogin ? 'Don\'t have an account? Sign Up' : 'Already have an account? Sign In',
                        style: TextStyle(color: Theme.of(context).hintColor),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          )
        ],
      ),
    );
  }
}

// Keep the RewardedAdTile functionality for ads
class RewardedAdTile extends StatefulWidget {
  final VoidCallback onAdWatched;
  const RewardedAdTile({super.key, required this.onAdWatched});

  @override
  State<RewardedAdTile> createState() => _RewardedAdTileState();
}

class _RewardedAdTileState extends State<RewardedAdTile> {
  RewardedAd? _rewardedAd;
  bool _isAdReady = false;
  bool _isLoading = false;
  bool onCooldown = false;
  Duration _remainingCooldown = Duration.zero;
  Timer? _cooldownTimer;
  Timer? _countdownTimer;
  
  final String _adUnitId = 'ca-app-pub-3940256099942544/5224354917'; // Test ad unit ID

  @override
  void initState() {
    super.initState();
    _loadCooldownState();
    _loadRewardedAd();
  }

  @override
  void dispose() {
    _rewardedAd?.dispose();
    _cooldownTimer?.cancel();
    _countdownTimer?.cancel();
    super.dispose();
  }

  void _loadCooldownState() async {
    final prefs = await SharedPreferences.getInstance();
    final lastAdWatchTime = prefs.getInt('last_ad_watch_time') ?? 0;
    final cooldownDuration = const Duration(hours: 2);
    final timeSinceLastAd = DateTime.now().millisecondsSinceEpoch - lastAdWatchTime;
    
    if (timeSinceLastAd < cooldownDuration.inMilliseconds) {
      final remainingTime = cooldownDuration.inMilliseconds - timeSinceLastAd;
      setState(() {
        onCooldown = true;
        _remainingCooldown = Duration(milliseconds: remainingTime);
      });
      _startCooldownTimer();
    }
  }

  void _startCooldownTimer() {
    _cooldownTimer = Timer(_remainingCooldown, () {
      if (mounted) {
        setState(() {
          onCooldown = false;
          _remainingCooldown = Duration.zero;
        });
      }
    });

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted && _remainingCooldown.inSeconds > 0) {
        setState(() {
          _remainingCooldown = Duration(seconds: _remainingCooldown.inSeconds - 1);
        });
      } else {
        timer.cancel();
      }
    });
  }

  void _loadRewardedAd() {
    RewardedAd.load(
      adUnitId: _adUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          ad.fullScreenContentCallback = FullScreenContentCallback(
            onAdShowedFullScreenContent: (ad) {},
            onAdImpression: (ad) {},
            onAdFailedToShowFullScreenContent: (ad, err) {
              ad.dispose();
              setState(() {
                _isAdReady = false;
                _isLoading = false;
              });
              _loadRewardedAd();
            },
            onAdDismissedFullScreenContent: (ad) {
              ad.dispose();
              setState(() {
                _isAdReady = false;
                _isLoading = false;
              });
              _loadRewardedAd();
            },
            onAdClicked: (ad) {},
          );

          setState(() {
            _rewardedAd = ad;
            _isAdReady = true;
            _isLoading = false;
          });
        },
        onAdFailedToLoad: (err) {
          setState(() {
            _isLoading = false;
          });
        },
      ),
    );
  }

  void _showRewardedAd() async {
    if (_rewardedAd == null || onCooldown) return;

    setState(() => _isLoading = true);

    await _rewardedAd!.show(
      onUserEarnedReward: (AdWithoutView ad, RewardItem reward) async {
        // Give some reward (can be points, unlock features, etc.)
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt('last_ad_watch_time', DateTime.now().millisecondsSinceEpoch);
        
        widget.onAdWatched();
        
        setState(() {
          onCooldown = true;
          _remainingCooldown = const Duration(hours: 2);
        });
        _startCooldownTimer();
      },
    );
  }

  String formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = twoDigits(duration.inHours);
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    return "${hours}h ${minutes}m";
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return ListTile(
      leading: Icon(
        CupertinoIcons.tv,
        color: onCooldown ? Colors.grey : (isDark ? const Color(0xFF10B981) : const Color(0xFF059669)),
      ),
      title: Text(onCooldown ? 'Next ad in ${formatDuration(_remainingCooldown)}' : 'Watch Ad for Rewards'),
      subtitle: Text(onCooldown ? 'Come back later to watch another ad' : 'Get rewards by watching a short video'),
      trailing: _isLoading 
        ? const CupertinoActivityIndicator()
        : Icon(
            CupertinoIcons.chevron_right,
            color: onCooldown ? Colors.grey : Theme.of(context).colorScheme.secondary,
          ),
      onTap: (!_isAdReady || onCooldown || _isLoading) ? null : _showRewardedAd,
    );
  }
}