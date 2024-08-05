import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class BottomNavigationBarWidget extends StatefulWidget {
  final PageController pageController;
  final ValueChanged<int> onTabTapped;
  final int currentIndex;
  const BottomNavigationBarWidget({
    super.key,
    required this.pageController,
    required this.onTabTapped,
    required this.currentIndex,
  });

  @override
  State<BottomNavigationBarWidget> createState() =>
      _BottomNavigationBarWidgetState();
}

class _BottomNavigationBarWidgetState extends State<BottomNavigationBarWidget>
    with TickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );

    _animation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeInOut,
      ),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant BottomNavigationBarWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Whenever currentIndex is updated from the parent widget, trigger the animation
    if (widget.currentIndex != oldWidget.currentIndex) {
      _animationController.reset();
      _animationController.forward();
    }
  }

  BottomNavigationBarItem buildNavItem(String iconPath, int index) {
    return BottomNavigationBarItem(
      icon: SizedBox(
        height: 36,
        child: Stack(
          children: [
            SvgPicture.asset(
              iconPath,
              width: 30,
              height: 30,
            ),
            if (widget.currentIndex ==
                index) // Show underline for the selected icon
              Positioned(
                top: 33,
                left: 0,
                right: 0,
                child: FadeTransition(
                  opacity: _animation,
                  child: SvgPicture.asset(
                    'assets/underline.svg',
                    width: 30,
                    height: 4,
                  ),
                ),
              ),
          ],
        ),
      ),
      // hack
      label: '',
      //end hack
    );
  }

  @override
  Widget build(BuildContext context) {
    return BottomNavigationBar(
      type: BottomNavigationBarType.fixed,
      items: [
        buildNavItem('assets/robots/terminal-page.svg', 0),
        buildNavItem('assets/robots/parameters-page.svg', 1),
        buildNavItem('assets/robots/notebook-page.svg', 2),
        buildNavItem('assets/robots/lineage-graph-page.svg', 3),
      ],
      currentIndex: widget.currentIndex,
      onTap: widget.onTabTapped,
    );
  }
}
