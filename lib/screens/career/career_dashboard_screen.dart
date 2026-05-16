import 'package:flutter/material.dart';
import '../../constants/app_colors.dart';
import 'add_task_screen.dart';
import 'edit_task_screen.dart';

class CareerDashboardScreen extends StatefulWidget {
  const CareerDashboardScreen({super.key});

  @override
  State<CareerDashboardScreen> createState() => _CareerDashboardScreenState();
}

class _CareerDashboardScreenState extends State<CareerDashboardScreen> {
  final List<Map<String, dynamic>> tasks = [
    {
      'title': 'Update portfolio profile',
      'category': 'Profile Setup',
      'date': 'May 5',
      'status': 'completed',
    },
    {
      'title': 'Upload resume document',
      'category': 'Documents',
      'date': 'May 10',
      'status': 'pending',
    },
    {
      'title': 'Add capstone project',
      'category': 'Portfolio',
      'date': 'May 15',
      'status': 'pending',
    },
    {
      'title': 'Review career profile',
      'category': 'Career',
      'date': 'May 1',
      'status': 'overdue',
    },
  ];

  List<Map<String, dynamic>> get pendingTasks {
    return tasks.where((task) => task['status'] == 'pending').toList();
  }

  List<Map<String, dynamic>> get overdueTasks {
    return tasks.where((task) => task['status'] == 'overdue').toList();
  }

  List<Map<String, dynamic>> get completedTasks {
    return tasks.where((task) => task['status'] == 'completed').toList();
  }

  double get progress {
    if (tasks.isEmpty) return 0;
    return completedTasks.length / tasks.length;
  }

  Future<void> goToAddTask() async {
    final newTask = await Navigator.push<Map<String, String>>(
      context,
      MaterialPageRoute(
        builder: (_) => const AddTaskScreen(),
      ),
    );

    if (!mounted) return;

    if (newTask != null) {
      setState(() {
        tasks.add({
          'title': newTask['title']!,
          'category': newTask['category']!,
          'date': newTask['date']!,
          'status': 'pending',
        });
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Task added successfully.'),
        ),
      );
    }
  }

  Future<void> goToEditTask(Map<String, dynamic> task) async {
    final updatedTask = await Navigator.push<Map<String, String>>(
      context,
      MaterialPageRoute(
        builder: (_) => EditTaskScreen(
          initialTitle: task['title'],
          initialCategory: task['category'],
          initialDate: task['date'],
        ),
      ),
    );

    if (!mounted) return;

    if (updatedTask != null) {
      setState(() {
        task['title'] = updatedTask['title']!;
        task['category'] = updatedTask['category']!;
        task['date'] = updatedTask['date']!;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Task updated successfully.'),
        ),
      );
    }
  }

  void deleteTask(Map<String, dynamic> task) {
    setState(() {
      tasks.remove(task);
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Task deleted.'),
      ),
    );
  }

  void toggleTaskStatus(Map<String, dynamic> task) {
    setState(() {
      if (task['status'] == 'completed') {
        task['status'] = 'pending';
      } else {
        task['status'] = 'completed';
      }
    });
  }

  Widget _taskCard({
    required Map<String, dynamic> task,
  }) {
    final bool isCompleted = task['status'] == 'completed';
    final bool isOverdue = task['status'] == 'overdue';

    Color statusColor = AppColors.input;
    IconData statusIcon = Icons.schedule;

    if (isCompleted) {
      statusColor = AppColors.success;
      statusIcon = Icons.check;
    } else if (isOverdue) {
      statusColor = AppColors.danger;
      statusIcon = Icons.warning_amber_rounded;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          InkWell(
            onTap: () => toggleTaskStatus(task),
            borderRadius: BorderRadius.circular(14),
            child: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: statusColor,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                statusIcon,
                color: AppColors.white,
                size: 22,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task['title'],
                  style: TextStyle(
                    color: AppColors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    decoration: isCompleted ? TextDecoration.lineThrough : null,
                    decorationColor: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  task['category'],
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                task['date'],
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  InkWell(
                    onTap: () => goToEditTask(task),
                    borderRadius: BorderRadius.circular(8),
                    child: const Icon(
                      Icons.edit_outlined,
                      color: AppColors.textMuted,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  InkWell(
                    onTap: () => deleteTask(task),
                    borderRadius: BorderRadius.circular(8),
                    child: const Icon(
                      Icons.delete_outline,
                      color: AppColors.textMuted,
                      size: 20,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _taskSection({
    required String title,
    required List<Map<String, dynamic>> sectionTasks,
    required String emptyText,
  }) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 22),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AppColors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 14),
          if (sectionTasks.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                emptyText,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                ),
              ),
            )
          else
            ...sectionTasks.map(
              (task) => _taskCard(task: task),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final progressPercent = (progress * 100).round();

    return Container(
      color: AppColors.background,
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 110),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Career Dashboard',
                style: TextStyle(
                  color: AppColors.white,
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 6),

              const Text(
                'Track your career preparation tasks.',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 14,
                ),
              ),

              const SizedBox(height: 22),

              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Task Progress',
                      style: TextStyle(
                        color: AppColors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${completedTasks.length} of ${tasks.length} tasks completed',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 18),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(30),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 12,
                        backgroundColor: AppColors.darkTeal,
                        color: AppColors.white,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '$progressPercent% completed',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: goToAddTask,
                  icon: const Icon(Icons.add),
                  label: const Text('Add Task'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.input,
                    foregroundColor: AppColors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 26),

              _taskSection(
                title: 'Task List',
                sectionTasks: pendingTasks,
                emptyText: 'No pending tasks.',
              ),

              _taskSection(
                title: 'Overdue Tasks',
                sectionTasks: overdueTasks,
                emptyText: 'No overdue tasks.',
              ),

              _taskSection(
                title: 'Completed Tasks',
                sectionTasks: completedTasks,
                emptyText: 'No completed tasks yet.',
              ),
            ],
          ),
        ),
      ),
    );
  }
}