// Replacement for llm_api_picker package using Google Generative AI (Gemini)

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LlmApi {
  final String name;
  final String? apiKey;
  final String? baseUrl;

  LlmApi({
    required this.name,
    this.apiKey,
    this.baseUrl,
  });
}

class Parameter {
  final String name;
  final String description;
  final String type;

  Parameter({
    required this.name,
    required this.description,
    required this.type,
  });
}

class FunctionInfo {
  final String name;
  final String description;
  final List<Parameter> parameters;
  final Function function;
  Map<String, dynamic>? parametersCalled;

  FunctionInfo({
    required this.name,
    required this.description,
    required this.parameters,
    required this.function,
    this.parametersCalled,
  });
}

enum MessageRole {
  user,
  model,
  system,
  assistant,
}

class Message {
  final MessageRole role;
  final String body;
  final String? attachedFile;

  Message({
    required this.role,
    required this.body,
    this.attachedFile,
  });

  Map<String, dynamic> toJson() {
    return {
      'role': role.toString().split('.').last,
      'body': body,
      'attachedFile': attachedFile,
    };
  }

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      role: MessageRole.values.firstWhere(
        (e) => e.toString().split('.').last == json['role'],
        orElse: () => MessageRole.user,
      ),
      body: json['body'] ?? '',
      attachedFile: json['attachedFile'],
    );
  }
}

class LLMRepository {
  static const String _apiKeyPrefsKey = 'gemini_api_key';
  
  LLMRepository();

  static Future<LlmApi?> getCurrentApi() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      String? apiKey = prefs.getString(_apiKeyPrefsKey);
      
      // Nếu không có trong SharedPreferences, thử lấy từ .env
      if (apiKey == null || apiKey.isEmpty) {
        try {
          apiKey = dotenv.env['GEMINI_API_KEY'];
        } catch (e) {
          // .env file might not be loaded or doesn't have the key
        }
      }
      
      if (apiKey != null && apiKey.isNotEmpty) {
        return LlmApi(name: 'Gemini', apiKey: apiKey);
      }
      
      return null;
    } catch (e) {
      return null;
    }
  }

  static Future<void> saveApiKey(String apiKey) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_apiKeyPrefsKey, apiKey);
  }

  static Future<String?> promptModel({
    required List<Message> messages,
    String? systemPrompt,
    required LlmApi api,
    bool returnJson = false,
    bool debugLogs = false,
  }) async {
    try {
      print('--- Gemini Request Start ---');
      print('API Name: ${api.name}');
      print('API Key present: ${api.apiKey != null && api.apiKey!.isNotEmpty}');
      if (api.apiKey != null && api.apiKey!.length > 5) {
        print('API Key prefix: ${api.apiKey!.substring(0, 5)}...');
      }
      print('System Prompt: $systemPrompt');
      print('Message Count: ${messages.length}');
      
      if (api.apiKey == null || api.apiKey!.isEmpty) {
        print('Error: API key is missing');
        throw Exception('API key is required');
      }

      GenerativeModel model;
      try {
        model = GenerativeModel(
          model: 'gemini-1.5-flash',
          apiKey: api.apiKey!,
          systemInstruction: systemPrompt != null ? Content.system(systemPrompt) : null,
          generationConfig: returnJson 
              ? GenerationConfig(responseMimeType: 'application/json')
              : null,
        );
      } catch (e) {
        // Fallback to gemini-pro if 1.5-flash fails initialization
        print('Error initializing gemini-1.5-flash, falling back to gemini-pro: $e');
        model = GenerativeModel(
          model: 'gemini-pro',
          apiKey: api.apiKey!,
          systemInstruction: systemPrompt != null ? Content.system(systemPrompt) : null,
        );
      }

      // Convert messages to Gemini format
      final chatHistory = <Content>[];
      for (int i = 0; i < messages.length - 1; i++) {
         final msg = messages[i];
         final role = msg.role == MessageRole.user ? 'user' : 'model';
         chatHistory.add(Content(role, [TextPart(msg.body)]));
      }

      // The last message is the new user message
      final lastMsg = messages.last;
      final content = Content.text(lastMsg.body);
      
      print('Sending message to Gemini (Model: ${model.model})...');
      final chat = model.startChat(history: chatHistory);
      
      GenerateContentResponse response;
      try {
        response = await chat.sendMessage(content);
      } catch (e) {
        if (e.toString().contains('404') || e.toString().contains('not found')) {
           print('Model not found, trying gemini-pro fallback...');
           // Try fallback to gemini-pro without JSON config
           final fallbackModel = GenerativeModel(
            model: 'gemini-pro',
            apiKey: api.apiKey!,
            systemInstruction: systemPrompt != null ? Content.system(systemPrompt) : null,
          );
          final fallbackChat = fallbackModel.startChat(history: chatHistory);
          response = await fallbackChat.sendMessage(content);
        } else {
          rethrow;
        }
      }
      
      print('Gemini Response received: ${response.text}');
      print('--- Gemini Request End ---');

      return response.text;
    } catch (e, stackTrace) {
      print('Error calling Gemini API: $e');
      print('Stack trace: $stackTrace');
      return returnJson ? '{}' : 'Error: $e';
    }
  }

  Future<(String, List<FunctionInfo>)> checkFunctionsCalling({
    required LlmApi api,
    required List<FunctionInfo> functions,
    required List<Message> messages,
    required String lastUserMessage,
  }) async {
    // Function calling implementation would go here
    // For now, return empty to avoid breaking the app
    return ('', <FunctionInfo>[]);
  }

  Future<(String, List<FunctionInfo>)> sendMessage({
    required List<Message> messages,
    List<FunctionInfo>? functions,
  }) async {
    final api = await getCurrentApi();
    if (api == null) {
      throw Exception('No API configured');
    }
    
    final response = await promptModel(
      messages: messages,
      api: api,
      debugLogs: true,
    );
    
    return (response ?? '', <FunctionInfo>[]);
  }
}

// Settings page for API configuration
class LlmApiPickerSettingsPage extends StatefulWidget {
  const LlmApiPickerSettingsPage({Key? key}) : super(key: key);

  @override
  State<LlmApiPickerSettingsPage> createState() => _LlmApiPickerSettingsPageState();
}

class _LlmApiPickerSettingsPageState extends State<LlmApiPickerSettingsPage> {
  final TextEditingController _apiKeyController = TextEditingController();
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadApiKey();
  }

  Future<void> _loadApiKey() async {
    setState(() => _isLoading = true);
    try {
      final api = await LLMRepository.getCurrentApi();
      if (api?.apiKey != null) {
        _apiKeyController.text = api!.apiKey!;
      }
    } catch (e) {
      // Ignore errors
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveApiKey() async {
    if (_apiKeyController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng nhập API key')),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      await LLMRepository.saveApiKey(_apiKeyController.text);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã lưu API key thành công!')),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cài đặt API Gemini'),
        actions: [
          if (!_isLoading)
            IconButton(
              icon: _isSaving 
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save),
              onPressed: _isSaving ? null : _saveApiKey,
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.key, size: 64, color: Colors.blue),
                  const SizedBox(height: 16),
                  const Text(
                    'Google Gemini API Key',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Nhập API key của bạn từ Google AI Studio để sử dụng Gemini.',
                    style: TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _apiKeyController,
                    decoration: InputDecoration(
                      labelText: 'API Key',
                      hintText: 'AIza...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      prefixIcon: const Icon(Icons.vpn_key),
                    ),
                    obscureText: true,
                  ),
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.info_outline, size: 20, color: Colors.blue[700]),
                              const SizedBox(width: 8),
                              const Text(
                                'Hướng dẫn lấy API key:',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          const Text('1. Truy cập: https://aistudio.google.com/app/apikey'),
                          const Text('2. Đăng nhập bằng tài khoản Google'),
                          const Text('3. Nhấn "Create API key"'),
                          const Text('4. Copy và dán vào ô bên trên'),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    super.dispose();
  }
}
