import 'dart:ui';
import 'dart:math'; // Import for pi
import 'package:aham/ui_widgets.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'notification_service.dart';
import 'theme.dart';

class NotificationScreen extends StatefulWidget {
  const NotificationScreen({super.key});

  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen> {
  late Future<List<NotificationModel>> _notificationsFuture;

  @override
  void initState() {
    super.initState();
    _refreshNotifications();
  }

  void _refreshNotifications() {
    setState(() { _notificationsFuture = NotificationService.fetchNotifications(); });
  }

  Future<void> _markAllAsRead(List<NotificationModel> notifications) async {
    await NotificationService.markAllAsRead(notifications);
    _refreshNotifications();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final style = SystemUiOverlayStyle(
      statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
    );

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        systemOverlayStyle: style,
        elevation: 0,
        backgroundColor: Colors.transparent,
        scrolledUnderElevation: 0,
        centerTitle: false,
        title: Text('Notifications', style: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 30,
          color: isDark ? Colors.white : Colors.grey[800],
        )),
        actions: [
          FutureBuilder<List<NotificationModel>>(
            future: _notificationsFuture,
            builder: (context, snapshot) {
              if (snapshot.hasData && snapshot.data!.isNotEmpty && NotificationService.hasUnread(snapshot.data!)) {
                return TextButton(onPressed: () => _markAllAsRead(snapshot.data!), child: const Text('Mark all read'));
              }
              return const SizedBox.shrink();
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          // --- UPDATED: Layering the correct background with the new blobs on top ---
          StaticGradientBackground(isDark: isDark),
          _AnimatedCoolBlobsBackground(isDark: isDark),

          SafeArea(
            bottom: false,
            child: FutureBuilder<List<NotificationModel>>(
              future: _notificationsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return _ShimmerLoadingState(isDark: isDark);
                }
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}', style: TextStyle(color: isDark ? Colors.white70 : Colors.black87)));
                }
                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return Center(
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(Icons.notifications_active_outlined, size: 70, color: isDark ? Colors.white54 : Colors.black38),
                      const SizedBox(height: 24),
                      Text('All caught up!', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22, color: isDark ? Colors.white : Colors.black87)),
                      const SizedBox(height: 8),
                      Text('You have no new notifications.', style: TextStyle(fontSize: 16, color: isDark ? Colors.white70 : Colors.black54)),
                    ]),
                  );
                }
                return CustomScrollView(
                  physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                  slivers: [
                    CupertinoSliverRefreshControl(
                      onRefresh: () async => _refreshNotifications(),
                    ),
                    _NotificationListView(notifications: snapshot.data!, onNotificationTap: _onNotificationTapped),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _onNotificationTapped(NotificationModel notification) async {
    if (!notification.isRead) {
      await NotificationService.markAsRead(notification.id);
      _refreshNotifications();
    }
    if (notification.actionUrl != null) {
      final uri = Uri.parse(notification.actionUrl!);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    }
  }
}

// --- UPDATED: New Background Widget ---
class _AnimatedCoolBlobsBackground extends StatefulWidget {
  final bool isDark;
  const _AnimatedCoolBlobsBackground({required this.isDark});

  @override
  State<_AnimatedCoolBlobsBackground> createState() => _AnimatedCoolBlobsBackgroundState();
}

class _AnimatedCoolBlobsBackgroundState extends State<_AnimatedCoolBlobsBackground> with TickerProviderStateMixin {
  late List<AnimationController> _positionControllers;
  late List<AnimationController> _rotationControllers;
  late List<Animation<double>> _rotationAnimations;

  @override
  void initState() {
    super.initState();
    _positionControllers = List.generate(2, (index) => AnimationController(vsync: this, duration: Duration(seconds: 25 + (index * 10)))..repeat(reverse: true));
    
    // Rotation controllers with different speeds
    _rotationControllers = [
      AnimationController(vsync: this, duration: const Duration(seconds: 30))..repeat(),
      AnimationController(vsync: this, duration: const Duration(seconds: 40))..repeat(),
    ];

    _rotationAnimations = _rotationControllers.map((controller) {
      return Tween<double>(begin: 0, end: 2 * pi).animate(controller);
    }).toList();
  }

  @override
  void dispose() {
    for (var controller in _positionControllers) { controller.dispose(); }
    for (var controller in _rotationControllers) { controller.dispose(); }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isDark) {
      return const SizedBox.shrink();
    }
    
    final colors = [Colors.pink.shade100, Colors.lightBlue.shade100];

    return Stack(children: [
      _buildBlob(
        positionController: _positionControllers[0],
        rotationAnimation: _rotationAnimations[0],
        color: colors[0],
        alignment: const Alignment(-1, -1),
        scale: 2.5
      ),
      _buildBlob(
        positionController: _positionControllers[1],
        rotationAnimation: _rotationAnimations[1],
        color: colors[1],
        alignment: const Alignment(1, 1),
        scale: 3.0
      ),
      BackdropFilter(filter: ImageFilter.blur(sigmaX: 60, sigmaY: 60), child: Container(color: Colors.transparent)),
    ]);
  }

  Widget _buildBlob({
    required AnimationController positionController,
    required Animation<double> rotationAnimation,
    required Color color,
    required Alignment alignment,
    required double scale
  }) {
    return AnimatedBuilder(
      animation: Listenable.merge([positionController, rotationAnimation]),
      builder: (context, child) {
        return Transform.rotate(
          angle: rotationAnimation.value,
          child: Transform.scale(
            scale: scale,
            child: Align(
              alignment: Alignment.lerp(alignment, -alignment, Curves.easeInOut.transform(positionController.value))!,
              child: Container(
                width: 200,
                height: 200,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
            ),
          ),
        );
      },
    );
  }
}


// --- Custom Shimmer Loading State ---
class _ShimmerLoadingState extends StatelessWidget {
  final bool isDark;
  const _ShimmerLoadingState({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      physics: const NeverScrollableScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) => _AnimatedListItem(
                index: index,
                child: Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(children: [
                    Container(width: 44, height: 44, decoration: BoxDecoration(color: isDark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.1), borderRadius: BorderRadius.circular(12))),
                    const SizedBox(width: 16),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Container(height: 16, width: 200, decoration: BoxDecoration(color: isDark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.1), borderRadius: BorderRadius.circular(8))),
                      const SizedBox(height: 10),
                      Container(height: 14, decoration: BoxDecoration(color: isDark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.1), borderRadius: BorderRadius.circular(8))),
                    ])),
                  ]),
                ),
              ),
              childCount: 5,
            ),
          ),
        ),
      ],
    );
  }
}

// --- Main List View ---
class _NotificationListView extends StatelessWidget {
  final List<NotificationModel> notifications;
  final Function(NotificationModel) onNotificationTap;
  const _NotificationListView({required this.notifications, required this.onNotificationTap});

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: const EdgeInsets.all(16),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final notification = notifications[index];
            return _AnimatedListItem(
              index: index,
              child: _NotificationItem(notification: notification, onTap: () => onNotificationTap(notification)),
            );
          },
          childCount: notifications.length,
        ),
      ),
    );
  }
}

// --- List Item Entry Animation Wrapper ---
class _AnimatedListItem extends StatefulWidget {
  final int index;
  final Widget child;
  const _AnimatedListItem({required this.index, required this.child});

  @override
  State<_AnimatedListItem> createState() => _AnimatedListItemState();
}

class _AnimatedListItemState extends State<_AnimatedListItem> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    final curve = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    _opacity = Tween<double>(begin: 0, end: 1).animate(curve);
    _slide = Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero).animate(curve);
    Future.delayed(Duration(milliseconds: widget.index * 100), () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() { _controller.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => FadeTransition(opacity: _opacity, child: SlideTransition(position: _slide, child: widget.child));
}

// --- Polished Glassmorphism Notification Item ---
class _NotificationItem extends StatelessWidget {
  final NotificationModel notification;
  final VoidCallback onTap;
  const _NotificationItem({required this.notification, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : const Color(0xFF1D1D1F);
    final subtextColor = isDark ? Colors.white.withOpacity(0.7) : Colors.black.withOpacity(0.6);
    final glassColor = isDark ? Colors.white.withOpacity(0.08) : Colors.white.withOpacity(0.9);
    final borderColor = isDark ? Colors.white.withOpacity(0.15) : Colors.white.withOpacity(0.8);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: onTap,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: glassColor, border: Border.all(color: borderColor, width: 1)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (notification.imageUrl != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16.0),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: AspectRatio(
                            aspectRatio: 16 / 9,
                            child: Image.network(notification.imageUrl!, fit: BoxFit.cover,
                              loadingBuilder: (_, c, p) => p == null ? c : Container(color: Colors.black12),
                              errorBuilder: (_, __, ___) => const SizedBox(),
                            ),
                          ),
                        ),
                      ),
                    Row(
                      children: [
                        if (!notification.isRead)
                          Container(width: 8, height: 8, margin: const EdgeInsets.only(right: 12), decoration: const BoxDecoration(color: Colors.blueAccent, shape: BoxShape.circle)),
                        Expanded(child: Text(notification.title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: textColor, letterSpacing: -0.2))),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(notification.message, style: TextStyle(color: subtextColor, height: 1.5, fontSize: 15)),
                    const SizedBox(height: 12),
                    Text(timeago.format(notification.timestamp), style: TextStyle(fontSize: 13, color: subtextColor.withOpacity(0.8))),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}