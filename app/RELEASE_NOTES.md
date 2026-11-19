# KeyDo 3.76

- **Keyboard safety fix:** KeyDo can no longer leave your keyboard stuck in other apps.
  - KeyDo only holds on to keys while its popup is really open. If a popup mode is left on by mistake (popup gone, nothing typed for a minute, or Escape pressed), it lets go at once.
  - If KeyDo itself ever freezes or is slow, its key watcher switches off by itself within a second and comes back when KeyDo responds again, so typing in other apps is never blocked.
  - A half-typed slash trigger expires after 30 seconds instead of staying on.
