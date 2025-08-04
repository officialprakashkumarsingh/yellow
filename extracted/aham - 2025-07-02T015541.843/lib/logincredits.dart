import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ahamai/ui_widgets.dart';

class CreditService {
  static final CreditService instance = CreditService._internal();
  factory CreditService() => instance;
  CreditService._internal();

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

  Future<int> getCredits() async {
    if (currentUser == null) return 0;
    try {
      final data = await _client.from('profiles').select('credits').eq('id', currentUser!.id).single();
      return data['credits'] as int;
    } catch (e) {
      return 0;
    }
  }

  Future<void> deductCredits(int amount) async {
    if (currentUser == null) return;
    final currentCredits = await getCredits();
    if (currentCredits >= amount) {
      final newCredits = currentCredits - amount;
      await _client.from('profiles').update({'credits': newCredits}).eq('id', currentUser!.id);
      await addCreditHistory(description: 'Action performed', amount: -amount);
    }
  }
  
  Future<void> addCredits(int amount, {String description = 'Credits added'}) async {
    if (currentUser == null) return;
    final currentCredits = await getCredits();
    final newCredits = currentCredits + amount;
    await _client.from('profiles').update({'credits': newCredits}).eq('id', currentUser!.id);
    await addCreditHistory(description: description, amount: amount);
  }
  
  Future<String> redeemCoupon(String code) async {
    if (currentUser == null) return 'error: You must be logged in.';
    try {
      final result = await _client.rpc('redeem_coupon_code', params: {'coupon_code': code});
      return result as String;
    } on PostgrestException catch (e) {
      // Handle potential RPC errors more gracefully
      return 'error: ${e.message}';
    } catch (e) {
      return 'error: An unexpected error occurred.';
    }
  }

  Future<void> addCreditHistory({required String description, required int amount}) async {
    if (currentUser == null) return;
    await _client.from('credit_history').insert({
      'user_id': currentUser!.id,
      'description': description,
      'amount': amount,
    });
  }

  Future<List<Map<String, dynamic>>> getCreditHistory() async {
    if (currentUser == null) return [];
    final response = await _client.from('credit_history').select().eq('user_id', currentUser!.id).order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(response);
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
        await CreditService.instance.signIn(email: _emailController.text, password: _passwordController.text);
      } else {
        await CreditService.instance.signUp(email: _emailController.text, password: _passwordController.text);
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
                      _isLogin ? 'Sign in to continue your journey with Aham.' : 'Sign up to get 500 free credits and start exploring.',
                       textAlign: TextAlign.center,
                       style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Theme.of(context).hintColor),
                    ),
                    const SizedBox(height: 32),
                    GlassmorphismPanel(
                      child: TextFormField(
                        controller: _emailController,
                        style: const TextStyle(fontSize: 16),
                        decoration: const InputDecoration(
                          hintText: 'Email', border: InputBorder.none, prefixIcon: Icon(CupertinoIcons.mail, size: 22), contentPadding: EdgeInsets.symmetric(vertical: 18),
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
                          hintText: 'Password', border: InputBorder.none, prefixIcon: Icon(CupertinoIcons.lock, size: 22), contentPadding: EdgeInsets.symmetric(vertical: 18),
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

class CreditHistoryScreen extends StatefulWidget {
  const CreditHistoryScreen({super.key});

  @override
  State<CreditHistoryScreen> createState() => _CreditHistoryScreenState();
}

class _CreditHistoryScreenState extends State<CreditHistoryScreen> {
  void _showCouponDialog() {
    final couponController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    bool isDialogLoading = false;

    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.3),
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return StyledDialog(
              title: 'Redeem Coupon',
              contentWidget: Form(
                key: formKey,
                child: TextFormField(
                  controller: couponController,
                  autofocus: true,
                  decoration: const InputDecoration(hintText: 'Enter your coupon code'),
                  validator: (value) => (value == null || value.trim().isEmpty) ? 'Cannot be empty' : null,
                  onFieldSubmitted: (v) async {
                    if (isDialogLoading) return;
                    if (formKey.currentState!.validate()) {
                      setDialogState(() => isDialogLoading = true);
                      final result = await CreditService.instance.redeemCoupon(couponController.text.trim());
                      if (mounted) {
                        _handleRedemptionResult(result, dialogContext);
                        setDialogState(() => isDialogLoading = false);
                      }
                    }
                  },
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: isDialogLoading ? null : () async {
                    if (formKey.currentState!.validate()) {
                      setDialogState(() => isDialogLoading = true);
                      final result = await CreditService.instance.redeemCoupon(couponController.text.trim());
                      if (mounted) {
                        _handleRedemptionResult(result, dialogContext);
                        setDialogState(() => isDialogLoading = false);
                      }
                    }
                  },
                  child: isDialogLoading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Redeem'),
                )
              ],
            );
          },
        );
      },
    );
  }

  void _handleRedemptionResult(String result, BuildContext dialogContext) {
    if (result.startsWith('success:')) {
      Navigator.of(dialogContext).pop(); // Close dialog on success
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(result.replaceFirst('success: ', ''), style: const TextStyle(color: Colors.white)),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
      ));
      // Refresh the history list
      setState(() {});
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(result.replaceFirst('error: ', ''), style: const TextStyle(color: Colors.white)),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final style = SystemUiOverlayStyle(statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: style,
      child: Scaffold(
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          systemOverlayStyle: style,
          title: const Text('Credit History'),
          centerTitle: true,
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          actions: [
            IconButton(
              icon: const Icon(CupertinoIcons.gift),
              tooltip: 'Redeem Coupon',
              onPressed: _showCouponDialog,
            )
          ],
        ),
        body: Stack(
          children: [
            StaticGradientBackground(isDark: isDark),
            SafeArea(
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: CreditService.instance.getCreditHistory(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError || !snapshot.hasData || snapshot.data!.isEmpty) {
                    return const Center(child: Text('No credit history found.'));
                  }
                  final history = snapshot.data!;
                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16.0, 8.0, 16.0, 16.0),
                    itemCount: history.length,
                    itemBuilder: (context, index) {
                      final item = history[index];
                      final amount = item['amount'] as int;
                      final isCredit = amount > 0;
                      final date = DateTime.parse(item['created_at']).toLocal();
                      final formattedDate = '${date.day}/${date.month}/${date.year}';
                      return Card(
                        elevation: 0,
                        color: Theme.of(context).cardColor.withOpacity(0.5),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        margin: const EdgeInsets.symmetric(vertical: 6),
                        child: ListTile(
                          leading: Icon(
                            isCredit ? CupertinoIcons.plus_circle_fill : CupertinoIcons.minus_circle_fill,
                            color: isCredit ? Colors.green : Colors.red,
                          ),
                          title: Text(item['description']),
                          subtitle: Text(formattedDate),
                          trailing: Text(
                            '${isCredit ? '+' : ''}$amount',
                            style: TextStyle(
                              color: isCredit ? Colors.green : Colors.red,
                              fontWeight: FontWeight.bold,
                              fontSize: 16
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class RewardedAdCreditTile extends StatefulWidget {
  final VoidCallback onCreditsAdded;
  const RewardedAdCreditTile({super.key, required this.onCreditsAdded});

  @override
  State<RewardedAdCreditTile> createState() => _RewardedAdCreditTileState();
}

class _RewardedAdCreditTileState extends State<RewardedAdCreditTile> {
  static const String adUnitId = 'ca-app-pub-3394897715416901/4102565339';
  static const int adRewardAmount = 25;
  static const Duration cooldownDuration = Duration(minutes: 30);
  
  RewardedAd? _rewardedAd;
  bool _isAdLoading = false;
  Timer? _cooldownTimer;
  Duration _remainingCooldown = Duration.zero;

  @override
  void initState() {
    super.initState();
    _checkCooldown();
  }

  Future<void> _checkCooldown() async {
    final prefs = await SharedPreferences.getInstance();
    final lastAdTimeMillis = prefs.getInt('last_ad_time') ?? 0;
    final lastAdTime = DateTime.fromMillisecondsSinceEpoch(lastAdTimeMillis);
    final now = DateTime.now();
    final difference = now.difference(lastAdTime);

    if (difference < cooldownDuration) {
      if (mounted) {
        setState(() => _remainingCooldown = cooldownDuration - difference);
        _startTimer();
      }
    } else {
      _loadAd();
    }
  }

  void _startTimer() {
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) {
        _cooldownTimer?.cancel();
        return;
      }

      if (_remainingCooldown.inSeconds > 0) {
        setState(() => _remainingCooldown = _remainingCooldown - const Duration(seconds: 1));
      } else {
        _cooldownTimer?.cancel();
        _loadAd();
        setState(() {});
      }
    });
  }

  void _loadAd() {
    if (!mounted) return;
    setState(() => _isAdLoading = true);
    RewardedAd.load(
      adUnitId: adUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _rewardedAd = ad;
          if (mounted) setState(() => _isAdLoading = false);
        },
        onAdFailedToLoad: (err) {
          if (mounted) setState(() => _isAdLoading = false);
        },
      ),
    );
  }
  
  void _showAd() {
    if (_rewardedAd == null) return;
    _rewardedAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _loadAd();
      },
      onAdFailedToShowFullScreenContent: (ad, err) {
        ad.dispose();
        _loadAd();
      },
    );
    _rewardedAd!.show(
      onUserEarnedReward: (ad, reward) async {
        await CreditService.instance.addCredits(adRewardAmount, description: 'Watched ad for credits');
        widget.onCreditsAdded();
        
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt('last_ad_time', DateTime.now().millisecondsSinceEpoch);
        
        if(mounted) {
          setState(() => _remainingCooldown = cooldownDuration);
          _startTimer();
        }
      },
    );
    _rewardedAd = null;
  }

  @override
  void dispose() {
    _rewardedAd?.dispose();
    _cooldownTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool onCooldown = _remainingCooldown.inSeconds > 0;
    final bool canShowAd = _rewardedAd != null && !_isAdLoading && !onCooldown;
    
    String formatDuration(Duration d) {
      String twoDigits(int n) => n.toString().padLeft(2, "0");
      String twoDigitMinutes = twoDigits(d.inMinutes.remainder(60));
      String twoDigitSeconds = twoDigits(d.inSeconds.remainder(60));
      return "$twoDigitMinutes:$twoDigitSeconds";
    }
    
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        CupertinoIcons.play_rectangle_fill,
        color: canShowAd ? Colors.blueAccent : Theme.of(context).disabledColor,
      ),
      title: Text(onCooldown ? 'Next ad in ${formatDuration(_remainingCooldown)}' : 'Watch Ad for $adRewardAmount Credits'),
      subtitle: _isAdLoading ? const Text('Loading ad...') : null,
      trailing: canShowAd ? const Icon(CupertinoIcons.chevron_forward, size: 18) : null,
      onTap: canShowAd ? _showAd : null,
    );
  }
}