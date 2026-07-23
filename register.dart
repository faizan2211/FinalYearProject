import 'package:flutter/material.dart';
import 'package:geo_assistant/LoginPage/login.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class Register extends StatefulWidget {
  const Register({super.key});

  @override
  _RegisterState createState() => _RegisterState();
}

class _RegisterState extends State<Register> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  Future<void> _registerUser() async {
    setState(() => _isLoading = true);
    
    try {
      final response = await http.post(
        Uri.parse('https://mongoose-colonial-deceit.ngrok-free.dev/register/'),
        headers: {
          'Content-Type': 'application/json',
          'ngrok-skip-browser-warning': 'true',
        },
        body: json.encode({
          'username': _emailController.text.trim(),
          'name': _nameController.text.trim(),
          'email': _emailController.text.trim(),
          'password': _passwordController.text,
        }),
      );

      final data = json.decode(response.body);

      if (response.statusCode == 201) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Registration Successful! Please login.")),
          );
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => Login()),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(data['error'] ?? "Registration Failed")),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Could not connect to server")),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF091F2C),
      body: Stack(
        children: [
          // Background Gradient
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF091F2C), Color(0xFF091F2C)],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: Center(
              child: SingleChildScrollView(
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 30),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(height: 50),
                        const Text(
                          "Register",
                          style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 40),
                        
                        SizedBox(
                          width: double.infinity,
                          child: TextFormField(
                            controller: _nameController,
                            decoration: InputDecoration(
                              hintText: "Name",
                              prefixIcon: const Icon(Icons.person, color: Colors.blueGrey),
                              filled: true,
                              fillColor: Colors.grey.shade100,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please enter your name';
                              }
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(height: 20),

                        SizedBox(
                          width: double.infinity,
                          child: TextFormField(
                            controller: _emailController,
                            decoration: InputDecoration(
                              hintText: "Email",
                              prefixIcon: const Icon(Icons.email, color: Colors.blueGrey),
                              filled: true,
                              fillColor: Colors.grey.shade100,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please enter your email';
                              }
                              if (!RegExp(
                                r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$',
                              ).hasMatch(value)) {
                                return 'Please enter a valid email address';
                              }
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(height: 20),

                        SizedBox(
                          width: double.infinity,
                          child: TextFormField(
                            controller: _passwordController,
                            obscureText: _obscurePassword,
                            decoration: InputDecoration(
                              hintText: "Password",
                              prefixIcon: const Icon(Icons.lock, color: Colors.blueGrey),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscurePassword ? Icons.visibility_off : Icons.visibility,
                                  color: Colors.blueGrey,
                                ),
                                onPressed: () {
                                  setState(() {
                                    _obscurePassword = !_obscurePassword;
                                  });
                                },
                              ),
                              filled: true,
                              fillColor: Colors.grey.shade100,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please enter your password';
                              }
                              if (value.length < 6) {
                                return 'Password must be at least 6 characters';
                              }
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(height: 20),

                        SizedBox(
                          width: double.infinity,
                          child: TextFormField(
                            controller: _confirmPasswordController,
                            obscureText: _obscureConfirmPassword,
                            decoration: InputDecoration(
                              hintText: "Confirm Password",
                              prefixIcon: const Icon(Icons.offline_pin_rounded, color: Colors.blueGrey),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscureConfirmPassword ? Icons.visibility_off : Icons.visibility,
                                  color: Colors.blueGrey,
                                ),
                                onPressed: () {
                                  setState(() {
                                    _obscureConfirmPassword = !_obscureConfirmPassword;
                                  });
                                },
                              ),
                              filled: true,
                              fillColor: Colors.grey.shade100,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please confirm your password';
                              }
                              if (value != _passwordController.text) {
                                return 'Passwords do not match';
                              }
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(height: 40),

                        SizedBox(
                          width: double.infinity,
                          child: _isLoading 
                            ? const Center(child: CircularProgressIndicator(color: Color(0xFF5DD6FF)))
                            : OutlinedButton(
                                onPressed: () {
                                  if (_formKey.currentState!.validate()) {
                                    _registerUser();
                                  }
                                },
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                  side: const BorderSide(color: Color(0xFF5DD6FF), width: 2),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: const Text(
                                  "Sign Up",
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF5DD6FF),
                                  ),
                                ),
                              ),
                        ),
                        const SizedBox(height: 20),
                        
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text(
                              "Already have an account? ",
                              style: TextStyle(color: Colors.white70),
                            ),
                            GestureDetector(
                              onTap: () {
                                Navigator.pop(context);
                              },
                              child: const Text(
                                "Login",
                                style: TextStyle(
                                  color: Color(0xFF5DD6FF),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }
}
