import 'package:flutter/material.dart';
import '../../constants/app_colors.dart';
import 'add_task_screen.dart';
import 'edit_task_screen.dart';

class TaskListScreen extends StatefulWidget {
  final List<Map<String, dynamic>> tasks;

  const TaskListScreen({
    super.key,
    required this.tasks,
  });

  @override
  State<TaskListScreen> createState() => _TaskListScreenState();
}

class _TaskListScreenState extends State<TaskListScreen> {
  List<Map<String, dynamic>> get pendingTasks {
    return widget.tasks.where((task) => task['status'] == 'pending').toList();
  }

  List<Map<String, dynamic>> get overdueTasks {
    return widget.tasks.where((task) => task['status'] == 'overdue').toList();
  }

  List<Map<String, dynamic>> get completedTasks {
    return widget.tasks
        .where((task) => task['status'] == 'completed')
        .toList();
  }

  Future<void> goToAddTask() async {
    final newTask = await Navigator.push<Map<String, String>>(
      context,
      MaterialPageRoute(
        builder: (_) => const AddTaskScreen(),
      ),
    );

    if (newTask != null) {
      setState(() {
        widget.tasks.add({
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
      widget.tasks.remove(task);
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

  Widget _summaryCard({
    required String value,
    required String label,
    required IconData icon,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          children: [
            Icon(icon, color: AppColors.white, size: 22),
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(
                color: AppColors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
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
    return Scaffold(
      backgroundColor: AppColors.background,
      floatingActionButton: FloatingActionButton(
        onPressed: goToAddTask,
        backgroundColor: AppColors.input,
        foregroundColor: AppColors.white,
        child: const Icon(Icons.add),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () {
                      Navigator.pop(context);
                    },
                    icon: const Icon(
                      Icons.arrow_back_ios_new,
                      color: AppColors.white,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Expanded(
                    child: Text(
                      'Task List',
                      style: TextStyle(
                        color: AppColors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 18),

              Row(
                children: [
                  _summaryCard(
                    value: '${widget.tasks.length}',
                    label: 'Total',
                    icon: Icons.task_alt_outlined,
                  ),
                  const SizedBox(width: 10),
                  _summaryCard(
                    value: '${overdueTasks.length}',
                    label: 'Overdue',
                    icon: Icons.warning_amber_rounded,
                  ),
                  const SizedBox(width: 10),
                  _summaryCard(
                    value: '${completedTasks.length}',
                    label: 'Completed',
                    icon: Icons.check_circle_outline,
                  ),
                ],
              ),

              const SizedBox(height: 24),

              _taskSection(
                title: 'Pending Tasks',
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