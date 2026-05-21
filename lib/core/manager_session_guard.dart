class ManagerSessionGuard {
  ManagerSessionGuard._();

  static bool _unlockedThisRuntime = false;

  static bool get isUnlockedThisRuntime => _unlockedThisRuntime;

  static void markUnlocked() {
    _unlockedThisRuntime = true;
  }

  static void reset() {
    _unlockedThisRuntime = false;
  }
}
