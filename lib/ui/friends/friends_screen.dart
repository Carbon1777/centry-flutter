import 'package:flutter/material.dart';

class FriendsScreen extends StatelessWidget {
  const FriendsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Друзья')),
      body: const Center(
        child: Text('Друзья\n\nВ разработке', textAlign: TextAlign.center),
      ),
    );
  }
}
