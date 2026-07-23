import 'package:flutter/material.dart';
import 'package:geo_assistant/LoginPage/login.dart';

class Splashscreen extends StatelessWidget {
  const Splashscreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      //     body: Container(
      //
      //         decoration: const BoxDecoration(
      //           image: DecorationImage(
      //             image: NetworkImage("https://images.unsplash.com/photo-1554629947-334ff61d85dc?q=80&w=436&auto=format&fit=crop&ixlib=rb-4.1.0&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D"),
      //             fit: BoxFit.cover,
      //           ),
      //         ),
      //         child: Center(
      //
      //           child:
      //             SizedBox(
      //
      //             child:ElevatedButton(
      //               onPressed: () {},
      //               style: ElevatedButton.styleFrom(
      //
      //                     elevation: 0,
      //                     backgroundColor: Colors.blueGrey,
      //
      //                 ),
      //
      //
      //           child: Text(
      //
      //             'Explore With Us',
      //             style: TextStyle(color: Colors.white, fontSize: 24),
      //
      //           ),
      //           ),
      //             ),
      //           ),
      //           ),
      //
      //
      // );
      body: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              image: DecorationImage(
                image: NetworkImage(
                  "https://images.unsplash.com/photo-1554629947-334ff61d85dc?q=80&w=436&auto=format&fit=crop&ixlib=rb-4.1.0&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D",
                ), // your image path
                fit: BoxFit.cover,
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(20),
            child: Align(
              alignment: Alignment.bottomCenter,
              child: SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => Login()),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    elevation: 0,
                    backgroundColor: Colors.blueGrey,
                  ),
                  child: Text(
                    'Explore With Us',
                    style: TextStyle(color: Colors.white, fontSize: 24),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
