import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

// МОДЕЛИ
class Todo {
  final int? id;
  final String description;
  final bool isCompleted;
  final DateTime createdAt;
  final DateTime? deadline;
  final Priority priority;
  final int? estimatedMinutes;

  Todo({
    this.id,
    required this.description,
    this.isCompleted = false,
    required this.createdAt,
    this.deadline,
    this.priority = Priority.medium,
    this.estimatedMinutes,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'description': description,
      'isCompleted': isCompleted ? 1 : 0,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'deadline': deadline?.millisecondsSinceEpoch,
      'priority': priority.index,
      'estimatedMinutes': estimatedMinutes,
    };
  }

  factory Todo.fromMap(Map<String, dynamic> map) {
    return Todo(
      id: map['id'],
      description: map['description'],
      isCompleted: map['isCompleted'] == 1,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['createdAt']),
      deadline: map['deadline'] != null 
          ? DateTime.fromMillisecondsSinceEpoch(map['deadline'])
          : null,
      priority: Priority.values[map['priority']],
      estimatedMinutes: map['estimatedMinutes'],
    );
  }

  Todo copyWith({
    int? id,
    String? description,
    bool? isCompleted,
    DateTime? createdAt,
    DateTime? deadline,
    Priority? priority,
    int? estimatedMinutes,
  }) {
    return Todo(
      id: id ?? this.id,
      description: description ?? this.description,
      isCompleted: isCompleted ?? this.isCompleted,
      createdAt: createdAt ?? this.createdAt,
      deadline: deadline ?? this.deadline,
      priority: priority ?? this.priority,
      estimatedMinutes: estimatedMinutes ?? this.estimatedMinutes,
    );
  }
}

enum Priority { low, medium, high }

// БД
class WebStorageService {
  static final WebStorageService _instance = WebStorageService._internal();
  factory WebStorageService() => _instance;
  WebStorageService._internal();

  static const String _todosKey = 'todos';

  Future<List<Todo>> getTodos() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? todosJson = prefs.getString(_todosKey);
      
      if (todosJson == null) return [];
      
      final List<dynamic> todosList = json.decode(todosJson);
      return todosList.map((todoMap) => Todo.fromMap(todoMap)).toList();
    } catch (e) {
      print('Error loading todos: $e');
      return [];
    }
  }

  Future<void> saveTodos(List<Todo> todos) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String todosJson = json.encode(todos.map((todo) => todo.toMap()).toList());
      await prefs.setString(_todosKey, todosJson);
    } catch (e) {
      print('Error saving todos: $e');
    }
  }

  Future<void> addTodo(Todo todo) async {
    final todos = await getTodos();
    todos.add(todo);
    await saveTodos(todos);
  }

  Future<void> updateTodo(Todo updatedTodo) async {
    final todos = await getTodos();
    final index = todos.indexWhere((todo) => todo.id == updatedTodo.id);
    if (index != -1) {
      todos[index] = updatedTodo;
      await saveTodos(todos);
    }
  }

  Future<void> deleteTodo(int id) async {
    final todos = await getTodos();
    todos.removeWhere((todo) => todo.id == id);
    await saveTodos(todos);
  }
}

// РЕПОЗИТОРИЙ
class TodoRepository {
  final WebStorageService _storageService;

  TodoRepository(this._storageService);

  Future<List<Todo>> getTodos() async {
    return await _storageService.getTodos();
  }

  Future<void> addTodo(Todo todo) async {
    // Генерируем ID для новой задачи
    final todos = await _storageService.getTodos();
    final newId = todos.isEmpty ? 1 : (todos.map((t) => t.id ?? 0).reduce((a, b) => a > b ? a : b) + 1);
    await _storageService.addTodo(todo.copyWith(id: newId));
  }

  Future<void> updateTodo(Todo todo) async {
    await _storageService.updateTodo(todo);
  }

  Future<void> deleteTodo(int id) async {
    await _storageService.deleteTodo(id);
  }

  Future<void> toggleTodoCompletion(int id) async {
    final todos = await _storageService.getTodos();
    final todo = todos.firstWhere((t) => t.id == id);
    await _storageService.updateTodo(todo.copyWith(isCompleted: !todo.isCompleted));
  }
}

// ПРОВАЙДЕРЫ
final storageServiceProvider = Provider<WebStorageService>((ref) => WebStorageService());

final todoRepositoryProvider = Provider<TodoRepository>((ref) {
  return TodoRepository(ref.read(storageServiceProvider));
});

final todosProvider = FutureProvider<List<Todo>>((ref) async {
  final repository = ref.read(todoRepositoryProvider);
  return await repository.getTodos();
});

final completedTodosCountProvider = Provider<int>((ref) {
  final todos = ref.watch(todosProvider).value ?? [];
  return todos.where((todo) => todo.isCompleted).length;
});

final analyticsProvider = Provider<Analytics>((ref) {
  final todos = ref.watch(todosProvider).value ?? [];
  return Analytics(todos);
});

class Analytics {
  final List<Todo> todos;

  Analytics(this.todos);

  int get completedCount => todos.where((todo) => todo.isCompleted).length;
  int get totalCount => todos.length;
  double get completionRate => totalCount > 0 ? completedCount / totalCount : 0;
  
  Map<String, int> get completionByPriority {
    final completed = todos.where((todo) => todo.isCompleted);
    final result = <String, int>{};
    for (final priority in Priority.values) {
      result[priority.name] = completed.where((todo) => todo.priority == priority).length;
    }
    return result;
  }
}

// ПРОВАЙДЕР ТЕМЫ
final themeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.light);

// ПРОВАЙДЕР РЕГИСТРАЦИИ
final authProvider = StateProvider<bool>((ref) => false);

// ВИДЖЕТЫ
void main() {
  // Инициализация для desktop-приложений
  runApp(
    const ProviderScope(
      child: PersonalAssistantApp(),
    ),
  );
}

class PersonalAssistantApp extends ConsumerWidget {
  const PersonalAssistantApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeProvider);
    final isAuthenticated = ref.watch(authProvider);

    return MaterialApp(
      title: 'Умный персональный ассистент',
      theme: ThemeData.light(),
      darkTheme: ThemeData.dark(),
      themeMode: themeMode,
      home: isAuthenticated ? const HomeScreen() : const LoginScreen(),
    );
  }
}

class LoginScreen extends ConsumerWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Вход в систему'),
        actions: [
          IconButton(
            icon: const Icon(Icons.brightness_6),
            onPressed: () {
              final currentTheme = ref.read(themeProvider);
              ref.read(themeProvider.notifier).state = 
                  currentTheme == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
            },
          ),
        ],
      ),
      body: const LoginForm(),
    );
  }
}

class LoginForm extends ConsumerStatefulWidget {
  const LoginForm({super.key});

  @override
  ConsumerState<LoginForm> createState() => _LoginFormState();
}

class _LoginFormState extends ConsumerState<LoginForm> {
  final _formKey = GlobalKey<FormState>();
  final _loginController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _loginController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextFormField(
              controller: _loginController,
              decoration: const InputDecoration(
                labelText: 'Логин',
                border: OutlineInputBorder(),
              ),
              validator: (String? value) {
                if (value == null || value.isEmpty) {
                  return 'Пожалуйста, введите логин';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _passwordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Пароль',
                border: OutlineInputBorder(),
              ),
              validator: (String? value) {
                if (value == null || value.isEmpty) {
                  return 'Пожалуйста, введите пароль';
                }
                return null;
              },
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                if (_formKey.currentState!.validate()) {
                  ref.read(authProvider.notifier).state = true;
                }
              },
              child: const Text('Войти'),
            ),
            TextButton(onPressed: () {
            Navigator.push(context, 
            MaterialPageRoute(builder: (context) => const RegisterScreen()),
            );
          },
          child: const Text("Регистрация")  
            ),
          ],
        ),
      ),
    );
  }
}

class RegisterScreen extends ConsumerWidget {
  const RegisterScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Регистрация в системе'),
        actions: [
          IconButton(
            icon: const Icon(Icons.brightness_6),
            onPressed: () {
              final currentTheme = ref.read(themeProvider);
              ref.read(themeProvider.notifier).state = 
                  currentTheme == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
            },
          ),
        ],
      ),
      body: const LoginForm(),
    );
  }
}

class RegisterFormState extends ConsumerState<LoginForm> {
  final _formKey = GlobalKey<FormState>();
  final _loginController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _loginController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextFormField(
              controller: _loginController,
              decoration: const InputDecoration(
                labelText: 'Регистрация',
                border: OutlineInputBorder(),
              ),
              validator: (String? value) {
                if (value == null || value.isEmpty) {
                  return 'Пожалуйста, введите имя';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _passwordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Пароль',
                border: OutlineInputBorder(),
              ),
              validator: (String? value) {
                if (value == null || value.isEmpty) {
                  return 'Пожалуйста, введите пароль';
                }
                return null;
              },
            ),
            const SizedBox(height: 24,),
            TextFormField(
              controller: _passwordController,
              obscureText: true,
              decoration: InputDecoration(
                labelText: 'Подтвердите пароль',
                border: OutlineInputBorder(),
              ),
              validator: (String? value){
                 if (value == null || value.isEmpty) {
                  return 'Пожалуйста, подтвердите пароль';
                }
                return null;
              },
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                if (_formKey.currentState!.validate()) {
                  ref.read(authProvider.notifier).state = true;
                }
              },
              child: const Text('Зарегистрироваться'),
            ),
            TextButton(onPressed: () {
            Navigator.push(context, 
            MaterialPageRoute(builder: (context) => const LoginScreen()),
            );
          },
          child: const Text("Войти")  
            ),
          ],
        ),
      ),
    );
  }
}

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Персональный ассистент'),
          actions: [
            IconButton(
              icon: const Icon(Icons.brightness_6),
              onPressed: () {
                final currentTheme = ref.read(themeProvider);
                ref.read(themeProvider.notifier).state = 
                    currentTheme == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
              },
            ),
            IconButton(
              icon: const Icon(Icons.exit_to_app),
              onPressed: () {
                ref.read(authProvider.notifier).state = false;
              },
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.dashboard), text: 'Дашборд'),
              Tab(icon: Icon(Icons.task), text: 'Задачи'),
              Tab(icon: Icon(Icons.analytics), text: 'Аналитика'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            DashboardScreen(),
            TodoListScreen(),
            AnalyticsScreen(),
          ],
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () {
            showDialog(
              context: context,
              builder: (BuildContext dialogContext) => const AddTodoDialog(),
            );
          },
          child: const Icon(Icons.add),
        ),
      ),
    );
  }
}


class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final todosAsync = ref.watch(todosProvider);
    final completedCount = ref.watch(completedTodosCountProvider);

    return todosAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => Center(child: Text('Ошибка: $error')),
      data: (todos) {
        return Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      const Text(
                        'Прогресс выполнения задач',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 16),
                      LinearProgressIndicator(
                        value: todos.isEmpty ? 0 : completedCount / todos.length,
                        backgroundColor: Colors.grey[300],
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '$completedCount из ${todos.length} задач выполнено',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Ближайшие задачи:',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: todos.length < 5 ? todos.length : 5,
                  itemBuilder: (BuildContext listContext, int index) {
                    final todo = todos[index];
                    return TodoCard(todo: todo);
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class TodoListScreen extends ConsumerWidget {
  const TodoListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final todosAsync = ref.watch(todosProvider);

    return todosAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => Center(child: Text('Ошибка: $error')),
      data: (todos) {
        if (todos.isEmpty) {
          return const Center(
            child: Text('Нет задач. Добавьте первую задачу!'),
          );
        }
        
        return ListView.builder(
          itemCount: todos.length,
          itemBuilder: (BuildContext listContext, int index) {
            final todo = todos[index];
            return Dismissible(
              key: Key(todo.id.toString()),
              background: Container(color: Colors.red),
              onDismissed: (DismissDirection direction) async {
                await ref.read(todoRepositoryProvider).deleteTodo(todo.id!);
                ref.invalidate(todosProvider);
              },
              child: TodoCard(todo: todo),
            );
          },
        );
      },
    );
  }
}

class TodoCard extends ConsumerWidget {
  final Todo todo;

  const TodoCard({super.key, required this.todo});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: ListTile(
        leading: Checkbox(
          value: todo.isCompleted,
          onChanged: (bool? value) async {
            await ref.read(todoRepositoryProvider).toggleTodoCompletion(todo.id!);
            ref.invalidate(todosProvider);
          },
        ),
        title: Text(
          todo.description,
          style: todo.isCompleted
              ? const TextStyle(decoration: TextDecoration.lineThrough)
              : null,
        ),
        subtitle: todo.deadline != null
            ? Text('До: ${DateFormat('dd.MM.yyyy').format(todo.deadline!)}')
            : null,
        trailing: _buildPriorityIndicator(todo.priority),
      ),
    );
  }

  Widget _buildPriorityIndicator(Priority priority) {
    final color = switch (priority) {
      Priority.high => Colors.red,
      Priority.medium => Colors.orange,
      Priority.low => Colors.green,
    };
    
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
    );
  }
}

class AnalyticsScreen extends ConsumerWidget {
  const AnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final analytics = ref.watch(analyticsProvider);
    final todosAsync = ref.watch(todosProvider);

    return todosAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => Center(child: Text('Ошибка: $error')),
      data: (todos) {
        return Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildStatCard(
                'Общая статистика',
                'Выполнено: ${analytics.completedCount} из ${analytics.totalCount}',
                'Процент выполнения: ${(analytics.completionRate * 100).toStringAsFixed(1)}%',
                Icons.analytics,
              ),
              const SizedBox(height: 16),
              _buildStatCard(
                'По приоритетам',
                'Высокий: ${analytics.completionByPriority['high'] ?? 0}',
                'Средний: ${analytics.completionByPriority['medium'] ?? 0}',
                Icons.priority_high,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatCard(String title, String subtitle1, String subtitle2, IconData icon) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            Icon(icon, size: 40),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  Text(subtitle1),
                  Text(subtitle2),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AddTodoDialog extends ConsumerStatefulWidget {
  const AddTodoDialog({super.key});

  @override
  ConsumerState<AddTodoDialog> createState() => _AddTodoDialogState();
}

class _AddTodoDialogState extends ConsumerState<AddTodoDialog> {
  final _formKey = GlobalKey<FormState>();
  final _descriptionController = TextEditingController();
  Priority _selectedPriority = Priority.medium;
  DateTime? _selectedDate;

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _addTodo() async {
    if (_formKey.currentState!.validate()) {
      final todo = Todo(
        description: _descriptionController.text,
        createdAt: DateTime.now(),
        deadline: _selectedDate,
        priority: _selectedPriority,
      );
      
      await ref.read(todoRepositoryProvider).addTodo(todo);
      ref.invalidate(todosProvider);
      
      Navigator.of(context).pop();
    }
  }

  Future<void> _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    
    if (picked != null && picked != _selectedDate && mounted) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Добавить задачу'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _descriptionController,
              decoration: const InputDecoration(labelText: 'Описание задачи'),
              validator: (String? value) {
                if (value == null || value.isEmpty) {
                  return 'Пожалуйста, введите описание';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<Priority>(
              initialValue: _selectedPriority,
              items: Priority.values.map((Priority priority) {
                return DropdownMenuItem<Priority>(
                  value: priority,
                  child: Text(_getPriorityText(priority)),
                );
              }).toList(),
              onChanged: (Priority? value) {
                setState(() {
                  _selectedPriority = value!;
                });
              },
              decoration: const InputDecoration(labelText: 'Приоритет'),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _selectedDate == null 
                        ? 'Без дедлайна' 
                        : 'Дедлайн: ${DateFormat('dd.MM.yyyy').format(_selectedDate!)}',
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.calendar_today),
                  onPressed: _selectDate,
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        ElevatedButton(
          onPressed: _addTodo,
          child: const Text('Добавить'),
        ),
      ],
    );
  }

  String _getPriorityText(Priority priority) {
    return switch (priority) {
      Priority.high => 'Высокий',
      Priority.medium => 'Средний',
      Priority.low => 'Низкий',
    };
  }
}
