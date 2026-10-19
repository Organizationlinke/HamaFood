# Hama Work - Task List Tab State Fix - 2026-10-19

## Fixes
1. Dashboard "Overdue Tasks" opens Team Tasks directly on the Overdue filter.
2. Dashboard "Ready Tasks" opens Team Tasks directly on Ready for Completion.
3. Tasks opened from any task-list filter now use `context.push()` instead of `context.go()` so the existing TasksScreen remains in the navigation stack.
4. Returning from Task Detail therefore restores the exact task-list filter/tab the user was viewing.
5. The existing overdue business rule remains unchanged: overdue is an independent derived/display filter and does not change `task.status`.

## Files changed
- lib/main.dart
- lib/screens/home_screen.dart
- lib/screens/tasks_screen.dart

## Validation
Flutter SDK was not available in the packaging environment, so `flutter analyze` could not be run here.
