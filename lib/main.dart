import 'package:flutter/material.dart';
import 'screens/chat_screen.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Iccountant',
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor:
            Colors.white, // Set the background color to white
      ),
      home: const MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          // Slim sidebar
          Container(
            width: 50,
            decoration: BoxDecoration(
              border: Border(
                right: BorderSide(
                  color: Colors.grey[300]!,
                  width: 1,
                ), // Thin right border
              ),
            ),
            child: Column(
              mainAxisAlignment:
                  MainAxisAlignment.start, // Move icons to the top
              children: [
                const SizedBox(
                  height: 100,
                ), // Adds space at the top of the sidebar
                IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: () {
                    // Action for search button
                  },
                ),
                const SizedBox(height: 1), // Adds space between icons
                IconButton(
                  icon: const Icon(Icons.settings),
                  onPressed: () {
                    // Navigate to settings screen
                  },
                ),
              ],
            ),
          ),

          // Main content area
          Expanded(child: ChatScreen()),
        ],
      ),
    );
  }
}
