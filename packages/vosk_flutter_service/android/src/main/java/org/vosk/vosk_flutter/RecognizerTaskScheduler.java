package org.vosk.vosk_flutter;

import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.PriorityQueue;
import java.util.concurrent.Callable;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicLong;

/**
 * Serializes native Vosk operations while allowing command work to overtake
 * queued free-text replay work between native calls.
 *
 * <p>The scheduler intentionally owns a single worker. Running two Vosk
 * decoders in parallel caused severe CPU/cache contention on the target
 * glasses. Priority is therefore applied at operation boundaries rather than
 * by executing command and replay inference concurrently.</p>
 *
 * <p>Calls for one recognizer remain FIFO even when its lane changes. Only the
 * head operation of each recognizer is eligible for global priority
 * scheduling, so reset/setGrammar/accept/getResult/close cannot reorder.</p>
 */
final class RecognizerTaskScheduler {
  enum Lane {
    COMMAND(0, "command"),
    DEFAULT(1, "default"),
    FREE_TEXT(2, "freeText"),
    SHUTDOWN(-100, "shutdown");

    private final int priority;
    private final String wireName;

    Lane(int priority, String wireName) {
      this.priority = priority;
      this.wireName = wireName;
    }

    int priority() {
      return priority;
    }

    String wireName() {
      return wireName;
    }

    static Lane forRecognizer(String requestedLane, String grammar) {
      if (hasCommandGrammar(grammar)) {
        return COMMAND;
      }
      if (requestedLane == null) {
        return DEFAULT;
      }
      final String normalized = requestedLane.trim().toLowerCase(Locale.ROOT);
      if ("command".equals(normalized)) {
        return COMMAND;
      }
      if ("freetext".equals(normalized)
          || "free_text".equals(normalized)
          || "free-text".equals(normalized)
          || "replay".equals(normalized)) {
        return FREE_TEXT;
      }
      return DEFAULT;
    }

    Lane promotedByGrammar(String grammar) {
      return hasCommandGrammar(grammar) ? COMMAND : this;
    }

    private static boolean hasCommandGrammar(String grammar) {
      if (grammar == null) {
        return false;
      }
      final String trimmed = grammar.trim();
      return !trimmed.isEmpty()
          && !"[]".equals(trimmed)
          && !"[ ]".equals(trimmed);
    }
  }

  interface Callback<T> {
    void onSuccess(T value);

    void onError(Exception error);
  }

  interface Logger {
    void log(boolean warning, String message);
  }

  static final class TaskCancelledException extends Exception {
    private static final long serialVersionUID = 1L;

    TaskCancelledException(String reason) {
      super(reason);
    }
  }

  static final class SchedulerClosedException extends Exception {
    private static final long serialVersionUID = 1L;

    SchedulerClosedException() {
      super("Recognizer task scheduler is closed");
    }
  }

  private static final long SLOW_QUEUE_WAIT_MS = 100L;
  private static final long SLOW_NATIVE_CALL_MS = 150L;
  // MethodChannel completion and the following Dart microtask are asynchronous.
  // Keep replay paused briefly after command work so acceptWaveForm ->
  // getPartial/getResult remains one effective command burst.
  private static final long COMMAND_HANDOFF_GRACE_MS = 150L;
  private static final int SHUTDOWN_RECOGNIZER_ID = Integer.MIN_VALUE;

  private final Object stateLock = new Object();
  private final PriorityQueue<ScheduledTask<?>> readyQueue =
      new PriorityQueue<>();
  private final Map<Integer, ArrayDeque<ScheduledTask<?>>> recognizerQueues =
      new HashMap<>();
  private final AtomicLong nextSequence = new AtomicLong();
  private final CountDownLatch terminated = new CountDownLatch(1);
  private final Logger logger;
  private final Thread worker;

  private volatile ScheduledTask<?> activeTask;
  private boolean accepting = true;
  private boolean shutdownScheduled;
  private int queuedTaskCount;
  private long commandHandoffUntilNanos;
  private boolean commandPriorityLease;

  RecognizerTaskScheduler(String threadName, Logger logger) {
    this.logger = logger;
    worker = new Thread(this::runWorker, threadName);
    worker.setDaemon(true);
    worker.start();
  }

  <T> boolean submit(
      int recognizerId,
      Lane lane,
      String operation,
      Callable<T> callable,
      Callback<T> callback) {
    final ScheduledTask<T> task = new ScheduledTask<>(
        nextSequence.incrementAndGet(),
        recognizerId,
        lane,
        operation,
        callable,
        callback,
        false);
    final ScheduledTask<?> active;
    final int queueDepth;
    final boolean commandBehindReplay;
    final boolean rejected;
    synchronized (stateLock) {
      rejected = !accepting;
      active = activeTask;
      if (rejected) {
        commandBehindReplay = false;
        queueDepth = queuedTaskCount;
      } else {
        commandBehindReplay = lane == Lane.COMMAND
            && ((active != null && active.lane == Lane.FREE_TEXT)
                || hasQueuedFreeTextLocked());
        if (commandBehindReplay
            || (lane == Lane.FREE_TEXT
                && active != null
                && active.lane == Lane.COMMAND)) {
          commandPriorityLease = true;
        }
        task.logLifecycle = commandBehindReplay || queuedTaskCount > 0;
        enqueueLocked(task);
        queueDepth = queuedTaskCount;
        stateLock.notifyAll();
      }
    }
    if (rejected) {
      invokeError(callback, new SchedulerClosedException(), task, "reject");
      return false;
    }
    if (task.logLifecycle) {
      logger.log(
          commandBehindReplay,
          "[VOSK_SCHEDULER] stage=queued seq=" + task.sequence
              + " recognizerId=" + recognizerId
              + " lane=" + lane.wireName()
              + " operation=" + operation
              + " queueDepth=" + queueDepth
              + " activeLane=" + (active == null ? "none" : active.lane.wireName())
              + " activeRecognizerId="
              + (active == null ? -1 : active.recognizerId)
              + " activeSeq="
              + (active == null ? -1 : active.sequence)
              + " activeOperation=" + (active == null ? "none" : active.operation)
              + " commandWaitingForReplay=" + commandBehindReplay);
    }
    return true;
  }

  /**
   * Stops accepting work, cancels queued work, runs cleanup after the active
   * native call returns, and then terminates the worker.
   */
  boolean shutdownAfterCurrent(Runnable cleanup, long timeoutMs) {
    final List<ScheduledTask<?>> cancelled = new ArrayList<>();
    boolean scheduleShutdown = false;
    synchronized (stateLock) {
      accepting = false;
      if (!shutdownScheduled) {
        shutdownScheduled = true;
        collectQueuedForCancellationLocked(cancelled);
        final ScheduledTask<Void> shutdownTask = new ScheduledTask<>(
            nextSequence.incrementAndGet(),
            SHUTDOWN_RECOGNIZER_ID,
            Lane.SHUTDOWN,
            "shutdown",
            () -> {
              cleanup.run();
              return null;
            },
            new Callback<Void>() {
              @Override
              public void onSuccess(Void value) {}

              @Override
              public void onError(Exception error) {
                logger.log(true,
                    "[VOSK_SCHEDULER] stage=shutdown_cleanup_failed error=" + error);
              }
            },
            true);
        enqueueLocked(shutdownTask);
        commandHandoffUntilNanos = 0L;
        commandPriorityLease = false;
        scheduleShutdown = true;
        stateLock.notifyAll();
      }
    }

    for (ScheduledTask<?> task : cancelled) {
      task.cancel("scheduler_shutdown", logger);
    }
    if (scheduleShutdown || !cancelled.isEmpty()) {
      final ScheduledTask<?> active = activeTask;
      logger.log(
          false,
          "[VOSK_SCHEDULER] stage=shutdown_requested cancelledQueued="
              + cancelled.size()
              + " activeLane="
              + (active == null ? "none" : active.lane.wireName())
              + " activeOperation="
              + (active == null ? "none" : active.operation));
    }

    try {
      final boolean completed = terminated.await(timeoutMs, TimeUnit.MILLISECONDS);
      if (!completed) {
        final ScheduledTask<?> active = activeTask;
        logger.log(
            true,
            "[VOSK_SCHEDULER] stage=shutdown_deferred timeoutMs=" + timeoutMs
                + " activeLane="
                + (active == null ? "none" : active.lane.wireName())
                + " activeOperation="
                + (active == null ? "none" : active.operation));
      }
      return completed;
    } catch (InterruptedException error) {
      Thread.currentThread().interrupt();
      logger.log(true,
          "[VOSK_SCHEDULER] stage=shutdown_interrupted error=" + error);
      return false;
    }
  }

  boolean isAccepting() {
    synchronized (stateLock) {
      return accepting;
    }
  }

  private void enqueueLocked(ScheduledTask<?> task) {
    ArrayDeque<ScheduledTask<?>> recognizerQueue =
        recognizerQueues.get(task.recognizerId);
    if (recognizerQueue == null) {
      recognizerQueue = new ArrayDeque<>();
      recognizerQueues.put(task.recognizerId, recognizerQueue);
    }
    final boolean isHead = recognizerQueue.isEmpty();
    recognizerQueue.addLast(task);
    queuedTaskCount++;
    if (isHead) {
      readyQueue.add(task);
    }
  }

  private void collectQueuedForCancellationLocked(
      List<ScheduledTask<?>> cancelled) {
    readyQueue.clear();
    final List<Integer> emptyRecognizerIds = new ArrayList<>();
    for (Map.Entry<Integer, ArrayDeque<ScheduledTask<?>>> entry
        : recognizerQueues.entrySet()) {
      final ArrayDeque<ScheduledTask<?>> recognizerQueue = entry.getValue();
      final ScheduledTask<?> active = activeTask;
      final boolean preserveActive = active != null
          && !recognizerQueue.isEmpty()
          && recognizerQueue.peekFirst() == active;
      if (preserveActive) {
        recognizerQueue.removeFirst();
        while (!recognizerQueue.isEmpty()) {
          cancelled.add(recognizerQueue.removeFirst());
          queuedTaskCount--;
        }
        recognizerQueue.addFirst(active);
      } else {
        while (!recognizerQueue.isEmpty()) {
          cancelled.add(recognizerQueue.removeFirst());
          queuedTaskCount--;
        }
        emptyRecognizerIds.add(entry.getKey());
      }
    }
    for (Integer recognizerId : emptyRecognizerIds) {
      recognizerQueues.remove(recognizerId);
    }
  }

  private void runWorker() {
    try {
      while (true) {
        final ScheduledTask<?> task;
        synchronized (stateLock) {
          task = takeNextReadyTaskLocked();
          if (task == null) {
            return;
          }
          activeTask = task;
          queuedTaskCount--;
        }

        final long startedAtNanos = System.nanoTime();
        final long waitMs = TimeUnit.NANOSECONDS.toMillis(
            startedAtNanos - task.enqueuedAtNanos);
        if (task.logLifecycle || waitMs >= SLOW_QUEUE_WAIT_MS) {
          logger.log(
              waitMs >= SLOW_QUEUE_WAIT_MS && task.lane == Lane.COMMAND,
              "[VOSK_SCHEDULER] stage=start seq=" + task.sequence
                  + " recognizerId=" + task.recognizerId
                  + " lane=" + task.lane.wireName()
                  + " operation=" + task.operation
                  + " waitMs=" + waitMs
                  + " queueDepth=" + queueDepth()
                  + " thread=" + Thread.currentThread().getName());
        }

        task.run(logger);
        final long runMs = TimeUnit.NANOSECONDS.toMillis(
            System.nanoTime() - startedAtNanos);
        if (task.logLifecycle
            || waitMs >= SLOW_QUEUE_WAIT_MS
            || runMs >= SLOW_NATIVE_CALL_MS) {
          logger.log(
              runMs >= SLOW_NATIVE_CALL_MS
                  || (waitMs >= SLOW_QUEUE_WAIT_MS && task.lane == Lane.COMMAND),
              "[VOSK_SCHEDULER] stage=done seq=" + task.sequence
                  + " recognizerId=" + task.recognizerId
                  + " lane=" + task.lane.wireName()
                  + " operation=" + task.operation
                  + " waitMs=" + waitMs
                  + " runMs=" + runMs
                  + " queueDepth=" + queueDepth()
                  + " thread=" + Thread.currentThread().getName());
        }

        synchronized (stateLock) {
          finishActiveTaskLocked(task);
          if (task.lane == Lane.COMMAND
              && commandPriorityLease
              && !shutdownScheduled) {
            commandHandoffUntilNanos = System.nanoTime()
                + TimeUnit.MILLISECONDS.toNanos(COMMAND_HANDOFF_GRACE_MS);
          }
          activeTask = null;
          stateLock.notifyAll();
        }
        if (task.terminal) {
          return;
        }
      }
    } finally {
      terminated.countDown();
      logger.log(false, "[VOSK_SCHEDULER] stage=terminated");
    }
  }

  private ScheduledTask<?> takeNextReadyTaskLocked() {
    while (true) {
      while (readyQueue.isEmpty()) {
        try {
          stateLock.wait();
        } catch (InterruptedException error) {
          Thread.currentThread().interrupt();
          logger.log(true,
              "[VOSK_SCHEDULER] stage=worker_interrupted error=" + error);
          return null;
        }
      }

      final ScheduledTask<?> next = readyQueue.peek();
      final long remainingGuardNanos = commandHandoffUntilNanos - System.nanoTime();
      if (commandPriorityLease
          && next != null
          && next.lane != Lane.COMMAND
          && next.lane != Lane.SHUTDOWN
          && remainingGuardNanos > 0L) {
        if (!next.handoffLogged) {
          next.handoffLogged = true;
          logger.log(
              false,
              "[VOSK_SCHEDULER] stage=command_handoff_hold recognizerId="
                  + next.recognizerId
                  + " lane="
                  + next.lane.wireName()
                  + " operation="
                  + next.operation
                  + " remainingMs="
                  + TimeUnit.NANOSECONDS.toMillis(remainingGuardNanos));
        }
        try {
          final long waitMs = TimeUnit.NANOSECONDS.toMillis(remainingGuardNanos);
          final int waitNanos = (int) (remainingGuardNanos
              - TimeUnit.MILLISECONDS.toNanos(waitMs));
          stateLock.wait(waitMs, waitNanos);
        } catch (InterruptedException error) {
          Thread.currentThread().interrupt();
          logger.log(true,
              "[VOSK_SCHEDULER] stage=worker_interrupted error=" + error);
          return null;
        }
        continue;
      }
      final ScheduledTask<?> selected = readyQueue.poll();
      if (selected != null
          && selected.lane == Lane.COMMAND
          && hasQueuedFreeTextLocked()) {
        commandPriorityLease = true;
      }
      if (selected != null
          && selected.lane != Lane.COMMAND
          && selected.lane != Lane.SHUTDOWN
          && commandPriorityLease) {
        commandPriorityLease = false;
        commandHandoffUntilNanos = 0L;
      }
      return selected;
    }
  }

  private boolean hasQueuedFreeTextLocked() {
    for (ArrayDeque<ScheduledTask<?>> recognizerQueue : recognizerQueues.values()) {
      for (ScheduledTask<?> queued : recognizerQueue) {
        if (queued != activeTask && queued.lane == Lane.FREE_TEXT) {
          return true;
        }
      }
    }
    return false;
  }

  private void finishActiveTaskLocked(ScheduledTask<?> task) {
    final ArrayDeque<ScheduledTask<?>> recognizerQueue =
        recognizerQueues.get(task.recognizerId);
    if (recognizerQueue == null || recognizerQueue.peekFirst() != task) {
      logger.log(
          true,
          "[VOSK_SCHEDULER] stage=fifo_invariant_failed recognizerId="
              + task.recognizerId
              + " seq="
              + task.sequence);
      return;
    }
    recognizerQueue.removeFirst();
    if (recognizerQueue.isEmpty()) {
      recognizerQueues.remove(task.recognizerId);
    } else {
      readyQueue.add(recognizerQueue.peekFirst());
    }
  }

  private int queueDepth() {
    synchronized (stateLock) {
      return queuedTaskCount;
    }
  }

  private <T> void invokeError(
      Callback<T> callback,
      Exception error,
      ScheduledTask<T> task,
      String stage) {
    try {
      callback.onError(error);
    } catch (RuntimeException callbackError) {
      logger.log(
          true,
          "[VOSK_SCHEDULER] stage=callback_failed callbackStage=" + stage
              + " recognizerId=" + task.recognizerId
              + " lane=" + task.lane.wireName()
              + " operation=" + task.operation
              + " error=" + callbackError);
    }
  }

  private static final class ScheduledTask<T>
      implements Comparable<ScheduledTask<?>> {
    private final long sequence;
    private final int recognizerId;
    private final Lane lane;
    private final String operation;
    private final Callable<T> callable;
    private final Callback<T> callback;
    private final boolean terminal;
    private final long enqueuedAtNanos = System.nanoTime();
    private final AtomicBoolean completed = new AtomicBoolean();
    private volatile boolean logLifecycle;
    private volatile boolean handoffLogged;

    ScheduledTask(
        long sequence,
        int recognizerId,
        Lane lane,
        String operation,
        Callable<T> callable,
        Callback<T> callback,
        boolean terminal) {
      this.sequence = sequence;
      this.recognizerId = recognizerId;
      this.lane = lane;
      this.operation = operation;
      this.callable = callable;
      this.callback = callback;
      this.terminal = terminal;
    }

    @Override
    public int compareTo(ScheduledTask<?> other) {
      final int priorityComparison = Integer.compare(
          lane.priority(), other.lane.priority());
      if (priorityComparison != 0) {
        return priorityComparison;
      }
      return Long.compare(sequence, other.sequence);
    }

    void run(Logger logger) {
      if (completed.get()) {
        return;
      }
      try {
        final T value = callable.call();
        if (completed.compareAndSet(false, true)) {
          try {
            callback.onSuccess(value);
          } catch (RuntimeException callbackError) {
            logCallbackFailure(logger, "success", callbackError);
          }
        }
      } catch (Exception error) {
        completeError(logger, error);
      } catch (Throwable error) {
        completeError(logger, new RuntimeException(error));
      }
    }

    void cancel(String reason, Logger logger) {
      completeError(logger, new TaskCancelledException(reason));
    }

    private void completeError(Logger logger, Exception error) {
      if (!completed.compareAndSet(false, true)) {
        return;
      }
      try {
        callback.onError(error);
      } catch (RuntimeException callbackError) {
        logCallbackFailure(logger, "error", callbackError);
      }
    }

    private void logCallbackFailure(
        Logger logger,
        String callbackStage,
        RuntimeException error) {
      logger.log(
          true,
          "[VOSK_SCHEDULER] stage=callback_failed callbackStage="
              + callbackStage
              + " recognizerId="
              + recognizerId
              + " lane="
              + lane.wireName()
              + " operation="
              + operation
              + " error="
              + error);
    }
  }
}
