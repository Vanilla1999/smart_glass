package org.vosk.vosk_flutter;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;
import org.junit.Test;

public class RecognizerTaskSchedulerTest {
  @Test
  public void commandOvertakesQueuedFreeTextAfterActiveReplay() throws Exception {
    final RecognizerTaskScheduler scheduler = scheduler();
    final List<String> order = Collections.synchronizedList(new ArrayList<>());
    final CountDownLatch activeStarted = new CountDownLatch(1);
    final CountDownLatch releaseActive = new CountDownLatch(1);
    final CountDownLatch completed = new CountDownLatch(3);

    scheduler.submit(
        2,
        RecognizerTaskScheduler.Lane.FREE_TEXT,
        "activeReplay",
        () -> {
          order.add("activeReplay");
          activeStarted.countDown();
          assertTrue(releaseActive.await(2, TimeUnit.SECONDS));
          return null;
        },
        callback(completed));
    assertTrue(activeStarted.await(2, TimeUnit.SECONDS));

    scheduler.submit(
        2,
        RecognizerTaskScheduler.Lane.FREE_TEXT,
        "queuedReplay",
        () -> {
          order.add("queuedReplay");
          return null;
        },
        callback(completed));
    scheduler.submit(
        1,
        RecognizerTaskScheduler.Lane.COMMAND,
        "command",
        () -> {
          order.add("command");
          return null;
        },
        callback(completed));

    releaseActive.countDown();
    assertTrue(completed.await(2, TimeUnit.SECONDS));
    assertEquals(
        java.util.Arrays.asList("activeReplay", "command", "queuedReplay"),
        order);
    assertTrue(scheduler.shutdownAfterCurrent(() -> {}, 2000));
  }

  @Test
  public void commandHandoffKeepsFollowUpResultCallAheadOfReplay()
      throws Exception {
    final RecognizerTaskScheduler scheduler = scheduler();
    final List<String> order = Collections.synchronizedList(new ArrayList<>());
    final CountDownLatch replayStarted = new CountDownLatch(1);
    final CountDownLatch releaseReplay = new CountDownLatch(1);
    final CountDownLatch completed = new CountDownLatch(4);

    scheduler.submit(
        2,
        RecognizerTaskScheduler.Lane.FREE_TEXT,
        "activeReplay",
        () -> {
          order.add("activeReplay");
          replayStarted.countDown();
          assertTrue(releaseReplay.await(2, TimeUnit.SECONDS));
          return null;
        },
        callback(completed));
    assertTrue(replayStarted.await(2, TimeUnit.SECONDS));

    scheduler.submit(
        2,
        RecognizerTaskScheduler.Lane.FREE_TEXT,
        "nextReplayBatch",
        () -> {
          order.add("replay");
          return null;
        },
        callback(completed));
    scheduler.submit(
        1,
        RecognizerTaskScheduler.Lane.COMMAND,
        "acceptWaveForm",
        () -> {
          order.add("commandAccept");
          return null;
        },
        new RecognizerTaskScheduler.Callback<Void>() {
          @Override
          public void onSuccess(Void value) {
            completed.countDown();
            final Thread roundTrip = new Thread(() -> {
              try {
                // Command PCM is batched at roughly 80 ms. The handoff lease
                // must keep replay paused across this MethodChannel gap.
                Thread.sleep(70);
              } catch (InterruptedException error) {
                Thread.currentThread().interrupt();
              }
              scheduler.submit(
                  1,
                  RecognizerTaskScheduler.Lane.COMMAND,
                  "getPartialResult",
                  () -> {
                    order.add("commandPartial");
                    return null;
                  },
                  callback(completed));
            });
            roundTrip.start();
          }

          @Override
          public void onError(Exception error) {
            completed.countDown();
          }
        });

    releaseReplay.countDown();
    assertTrue(completed.await(3, TimeUnit.SECONDS));
    assertEquals(
        java.util.Arrays.asList(
            "activeReplay", "commandAccept", "commandPartial", "replay"),
        order);
    assertTrue(scheduler.shutdownAfterCurrent(() -> {}, 2000));
  }

  @Test
  public void replayQueuedDuringCommandWaitsForCommandFollowUp()
      throws Exception {
    final RecognizerTaskScheduler scheduler = scheduler();
    final List<String> order = Collections.synchronizedList(new ArrayList<>());
    final CountDownLatch commandStarted = new CountDownLatch(1);
    final CountDownLatch releaseCommand = new CountDownLatch(1);
    final CountDownLatch completed = new CountDownLatch(3);

    scheduler.submit(
        1,
        RecognizerTaskScheduler.Lane.COMMAND,
        "acceptWaveForm",
        () -> {
          order.add("commandAccept");
          commandStarted.countDown();
          assertTrue(releaseCommand.await(2, TimeUnit.SECONDS));
          return null;
        },
        new RecognizerTaskScheduler.Callback<Void>() {
          @Override
          public void onSuccess(Void value) {
            completed.countDown();
            final Thread roundTrip = new Thread(() -> {
              try {
                Thread.sleep(70);
              } catch (InterruptedException error) {
                Thread.currentThread().interrupt();
              }
              scheduler.submit(
                  1,
                  RecognizerTaskScheduler.Lane.COMMAND,
                  "getPartialResult",
                  () -> {
                    order.add("commandPartial");
                    return null;
                  },
                  callback(completed));
            });
            roundTrip.start();
          }

          @Override
          public void onError(Exception error) {
            completed.countDown();
          }
        });
    assertTrue(commandStarted.await(2, TimeUnit.SECONDS));

    scheduler.submit(
        2,
        RecognizerTaskScheduler.Lane.FREE_TEXT,
        "replayQueuedDuringCommand",
        () -> {
          order.add("replay");
          return null;
        },
        callback(completed));

    releaseCommand.countDown();
    assertTrue(completed.await(3, TimeUnit.SECONDS));
    assertEquals(
        java.util.Arrays.asList("commandAccept", "commandPartial", "replay"),
        order);
    assertTrue(scheduler.shutdownAfterCurrent(() -> {}, 2000));
  }

  @Test
  public void oneRecognizerRemainsFifoAcrossLanePromotion() throws Exception {
    final RecognizerTaskScheduler scheduler = scheduler();
    final List<String> order = Collections.synchronizedList(new ArrayList<>());
    final CountDownLatch blockerStarted = new CountDownLatch(1);
    final CountDownLatch releaseBlocker = new CountDownLatch(1);
    final CountDownLatch completed = new CountDownLatch(3);

    scheduler.submit(
        9,
        RecognizerTaskScheduler.Lane.FREE_TEXT,
        "blocker",
        () -> {
          blockerStarted.countDown();
          assertTrue(releaseBlocker.await(2, TimeUnit.SECONDS));
          return null;
        },
        callback(completed));
    assertTrue(blockerStarted.await(2, TimeUnit.SECONDS));

    scheduler.submit(
        1,
        RecognizerTaskScheduler.Lane.DEFAULT,
        "reset",
        () -> {
          order.add("reset");
          return null;
        },
        callback(completed));
    scheduler.submit(
        1,
        RecognizerTaskScheduler.Lane.COMMAND,
        "setGrammar",
        () -> {
          order.add("setGrammar");
          return null;
        },
        callback(completed));

    releaseBlocker.countDown();
    assertTrue(completed.await(2, TimeUnit.SECONDS));
    assertEquals(java.util.Arrays.asList("reset", "setGrammar"), order);
    assertTrue(scheduler.shutdownAfterCurrent(() -> {}, 2000));
  }

  @Test
  public void nativeOperationsNeverRunConcurrently() throws Exception {
    final RecognizerTaskScheduler scheduler = scheduler();
    final AtomicInteger active = new AtomicInteger();
    final AtomicInteger maxActive = new AtomicInteger();
    final CountDownLatch completed = new CountDownLatch(20);

    for (int index = 0; index < 20; index++) {
      final RecognizerTaskScheduler.Lane lane = index % 2 == 0
          ? RecognizerTaskScheduler.Lane.COMMAND
          : RecognizerTaskScheduler.Lane.FREE_TEXT;
      scheduler.submit(
          index,
          lane,
          "operation" + index,
          () -> {
            final int now = active.incrementAndGet();
            maxActive.accumulateAndGet(now, Math::max);
            Thread.sleep(5);
            active.decrementAndGet();
            return null;
          },
          callback(completed));
    }

    assertTrue(completed.await(3, TimeUnit.SECONDS));
    assertEquals(1, maxActive.get());
    assertTrue(scheduler.shutdownAfterCurrent(() -> {}, 2000));
  }

  @Test
  public void callbackFailureDoesNotTerminateWorker() throws Exception {
    final RecognizerTaskScheduler scheduler = scheduler();
    final CountDownLatch secondCompleted = new CountDownLatch(1);

    scheduler.submit(
        1,
        RecognizerTaskScheduler.Lane.COMMAND,
        "badCallback",
        () -> null,
        new RecognizerTaskScheduler.Callback<Void>() {
          @Override
          public void onSuccess(Void value) {
            throw new IllegalStateException("test callback failure");
          }

          @Override
          public void onError(Exception error) {
            throw new IllegalStateException("unexpected error callback", error);
          }
        });
    scheduler.submit(
        2,
        RecognizerTaskScheduler.Lane.FREE_TEXT,
        "stillRuns",
        () -> null,
        callback(secondCompleted));

    assertTrue(secondCompleted.await(2, TimeUnit.SECONDS));
    assertTrue(scheduler.shutdownAfterCurrent(() -> {}, 2000));
  }

  @Test
  public void shutdownCancelsQueuedWorkAndCleansAfterActiveCall() throws Exception {
    final RecognizerTaskScheduler scheduler = scheduler();
    final CountDownLatch activeStarted = new CountDownLatch(1);
    final CountDownLatch releaseActive = new CountDownLatch(1);
    final CountDownLatch activeCompleted = new CountDownLatch(1);
    final CountDownLatch cancelled = new CountDownLatch(2);
    final CountDownLatch cleanup = new CountDownLatch(1);

    scheduler.submit(
        2,
        RecognizerTaskScheduler.Lane.FREE_TEXT,
        "activeReplay",
        () -> {
          activeStarted.countDown();
          assertTrue(releaseActive.await(2, TimeUnit.SECONDS));
          return null;
        },
        callback(activeCompleted));
    assertTrue(activeStarted.await(2, TimeUnit.SECONDS));

    scheduler.submit(
        1,
        RecognizerTaskScheduler.Lane.COMMAND,
        "queuedCommand",
        () -> null,
        cancellationCallback(cancelled));
    scheduler.submit(
        2,
        RecognizerTaskScheduler.Lane.FREE_TEXT,
        "queuedReplay",
        () -> null,
        cancellationCallback(cancelled));

    final AtomicInteger shutdownResult = new AtomicInteger(-1);
    final Thread shutdownThread = new Thread(() -> shutdownResult.set(
        scheduler.shutdownAfterCurrent(cleanup::countDown, 2000) ? 1 : 0));
    shutdownThread.start();

    assertTrue(cancelled.await(2, TimeUnit.SECONDS));
    assertFalse(scheduler.isAccepting());
    releaseActive.countDown();
    shutdownThread.join(3000);

    assertEquals(1, shutdownResult.get());
    assertTrue(activeCompleted.await(1, TimeUnit.SECONDS));
    assertEquals(0, cleanup.getCount());
  }

  @Test
  public void logsWhenCommandWaitsForActiveReplay() throws Exception {
    final List<String> logs = Collections.synchronizedList(new ArrayList<>());
    final RecognizerTaskScheduler scheduler = new RecognizerTaskScheduler(
        "test-vosk-scheduler",
        (warning, message) -> logs.add(message));
    final CountDownLatch activeStarted = new CountDownLatch(1);
    final CountDownLatch releaseActive = new CountDownLatch(1);
    final CountDownLatch completed = new CountDownLatch(2);

    scheduler.submit(
        2,
        RecognizerTaskScheduler.Lane.FREE_TEXT,
        "activeReplay",
        () -> {
          activeStarted.countDown();
          releaseActive.await(2, TimeUnit.SECONDS);
          return null;
        },
        callback(completed));
    assertTrue(activeStarted.await(2, TimeUnit.SECONDS));
    scheduler.submit(
        1,
        RecognizerTaskScheduler.Lane.COMMAND,
        "command",
        () -> null,
        callback(completed));

    assertTrue(logs.stream().anyMatch(
        message -> message.contains("commandWaitingForReplay=true")));
    releaseActive.countDown();
    assertTrue(completed.await(2, TimeUnit.SECONDS));
    assertTrue(scheduler.shutdownAfterCurrent(() -> {}, 2000));
  }

  @Test
  public void rejectsNewWorkAfterShutdown() {
    final RecognizerTaskScheduler scheduler = scheduler();
    assertTrue(scheduler.shutdownAfterCurrent(() -> {}, 2000));
    final AtomicInteger closedErrors = new AtomicInteger();

    final boolean accepted = scheduler.submit(
        1,
        RecognizerTaskScheduler.Lane.COMMAND,
        "lateCommand",
        () -> null,
        new RecognizerTaskScheduler.Callback<Void>() {
          @Override
          public void onSuccess(Void value) {}

          @Override
          public void onError(Exception error) {
            if (error instanceof RecognizerTaskScheduler.SchedulerClosedException) {
              closedErrors.incrementAndGet();
            }
          }
        });

    assertFalse(accepted);
    assertEquals(1, closedErrors.get());
  }

  @Test
  public void recognizerLaneIsPromotedByNonEmptyGrammar() {
    assertEquals(
        RecognizerTaskScheduler.Lane.DEFAULT,
        RecognizerTaskScheduler.Lane.forRecognizer(null, null));
    assertEquals(
        RecognizerTaskScheduler.Lane.COMMAND,
        RecognizerTaskScheduler.Lane.forRecognizer(null, "[\"назад\"]"));
    assertEquals(
        RecognizerTaskScheduler.Lane.FREE_TEXT,
        RecognizerTaskScheduler.Lane.forRecognizer("free-text", null));
    assertEquals(
        RecognizerTaskScheduler.Lane.COMMAND,
        RecognizerTaskScheduler.Lane.FREE_TEXT.promotedByGrammar(
            "[\"жёлтый\"]"));
    assertEquals(
        RecognizerTaskScheduler.Lane.FREE_TEXT,
        RecognizerTaskScheduler.Lane.FREE_TEXT.promotedByGrammar("[]"));
  }

  private RecognizerTaskScheduler scheduler() {
    return new RecognizerTaskScheduler(
        "test-vosk-scheduler",
        (warning, message) -> {});
  }

  private RecognizerTaskScheduler.Callback<Void> callback(CountDownLatch done) {
    return new RecognizerTaskScheduler.Callback<Void>() {
      @Override
      public void onSuccess(Void value) {
        done.countDown();
      }

      @Override
      public void onError(Exception error) {
        done.countDown();
      }
    };
  }

  private RecognizerTaskScheduler.Callback<Void> cancellationCallback(
      CountDownLatch cancelled) {
    return new RecognizerTaskScheduler.Callback<Void>() {
      @Override
      public void onSuccess(Void value) {}

      @Override
      public void onError(Exception error) {
        if (error instanceof RecognizerTaskScheduler.TaskCancelledException) {
          cancelled.countDown();
        }
      }
    };
  }
}
