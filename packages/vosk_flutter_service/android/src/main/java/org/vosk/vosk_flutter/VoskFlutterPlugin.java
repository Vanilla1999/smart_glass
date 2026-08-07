package org.vosk.vosk_flutter;

import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;
import android.util.Log;

import androidx.annotation.NonNull;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.StandardMethodCodec;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;

import java.io.IOException;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.TreeMap;
import java.util.concurrent.Callable;

import org.vosk.Model;
import org.vosk.Recognizer;
import org.vosk.SpeakerModel;
import org.vosk.android.SpeechService;
import org.vosk.vosk_flutter.exceptions.MissingRequiredArgument;
import org.vosk.vosk_flutter.exceptions.RecognizerNotFound;
import org.vosk.vosk_flutter.exceptions.SpeechServiceNotFound;
import org.vosk.vosk_flutter.exceptions.WrongArgumentTypeException;

/** Vosk Flutter plugin. */
public class VoskFlutterPlugin implements FlutterPlugin, MethodCallHandler {

  private static final String TAG = "VoskFlutterPlugin";
  private static final long DETACH_SCHEDULER_TIMEOUT_MS = 250L;

  @SuppressWarnings("unchecked")
  private static final Class<HashMap<String, Object>> argsMapClass =
      (Class<HashMap<String, Object>>) new HashMap<String, Object>().getClass();

  private final HashMap<String, Model> modelsMap = new HashMap<>();
  private final HashMap<String, SpeakerModel> speakerModelsMap = new HashMap<>();
  private final TreeMap<Integer, ManagedRecognizer> recognizersMap = new TreeMap<>();
  private final Object lifecycleLock = new Object();
  private final Handler mainHandler = new Handler(Looper.getMainLooper());

  private MethodChannel channel;
  private SpeechService speechService;
  private ManagedRecognizer speechServiceRecognizer;
  private FlutterRecognitionListener recognitionListener;
  private RecognizerTaskScheduler recognizerScheduler;
  private boolean attached;
  private int engineGeneration;
  private int nextRecognizerId = 1;

  @Override
  public void onAttachedToEngine(@NonNull FlutterPluginBinding flutterPluginBinding) {
    synchronized (lifecycleLock) {
      if (attached) {
        throw new IllegalStateException("VoskFlutterPlugin is already attached");
      }
      final int generation = ++engineGeneration;
      recognizerScheduler = new RecognizerTaskScheduler(
          "vosk-priority-" + generation,
          (warning, message) -> {
            if (warning) {
              Log.w(TAG, message);
            } else {
              Log.i(TAG, message);
            }
          });
      channel = new MethodChannel(
          flutterPluginBinding.getBinaryMessenger(),
          "vosk_flutter",
          StandardMethodCodec.INSTANCE,
          flutterPluginBinding.getBinaryMessenger().makeBackgroundTaskQueue());
      channel.setMethodCallHandler(this);
      recognitionListener =
          new FlutterRecognitionListener(flutterPluginBinding.getBinaryMessenger());
      attached = true;
      Log.i(TAG, "[VOSK_SCHEDULER] stage=attached generation=" + generation);
    }
  }

  @Override
  public void onMethodCall(@NonNull MethodCall call, @NonNull Result result) {
    if (call.method.startsWith("recognizer.")) {
      handleRecognizerMethod(call, result);
      return;
    }
    if ("speechService.init".equals(call.method)) {
      handleSpeechServiceInit(call, result);
      return;
    }

    synchronized (lifecycleLock) {
      if (!attached) {
        result.error("PLUGIN_DETACHED", "Vosk plugin is detached", null);
        return;
      }

      try {
        switch (call.method) {
          case "model.create": {
            final String modelPath = castMethodCallArgs(call, String.class);
            if (modelPath == null) {
              result.error(
                  "WRONG_ARGS",
                  "Please, send 1 string argument, contains model path",
                  null);
              break;
            }

            final int generation = engineGeneration;
            try {
              final Model model = new Model(modelPath);
              modelsMap.put(modelPath, model);
              postChannelMethod(generation, "model.created", modelPath);
            } catch (IOException exception) {
              final HashMap<String, Object> error = new HashMap<>();
              error.put("modelPath", modelPath);
              error.put("error", exception.getMessage());
              postChannelMethod(generation, "model.error", error);
            }

            result.success(null);
          }
          break;

          case "speakerModel.create": {
            final String modelPath = castMethodCallArgs(call, String.class);
            if (modelPath == null) {
              result.error(
                  "WRONG_ARGS",
                  "Please, send 1 string argument, contains speaker model path",
                  null);
              break;
            }

            final int generation = engineGeneration;
            try {
              final SpeakerModel speakerModel = new SpeakerModel(modelPath);
              speakerModelsMap.put(modelPath, speakerModel);
              postChannelMethod(generation, "speakerModel.created", modelPath);
            } catch (IOException exception) {
              final HashMap<String, Object> error = new HashMap<>();
              error.put("speakerModelPath", modelPath);
              error.put("error", exception.getMessage());
              postChannelMethod(generation, "speakerModel.error", error);
            }

            result.success(null);
          }
          break;

          case "speechService.start": {
            if (speechService == null) {
              throw new SpeechServiceNotFound();
            }
            result.success(speechService.startListening(recognitionListener));
          }
          break;

          case "speechService.stop": {
            if (speechService == null) {
              throw new SpeechServiceNotFound();
            }
            result.success(speechService.stop());
          }
          break;

          case "speechService.setPause": {
            if (speechService == null) {
              throw new SpeechServiceNotFound();
            }
            final Boolean paused = castMethodCallArgs(call, Boolean.class);
            speechService.setPause(paused);
            result.success(null);
          }
          break;

          case "speechService.reset": {
            if (speechService == null) {
              throw new SpeechServiceNotFound();
            }
            speechService.reset();
            result.success(null);
          }
          break;

          case "speechService.cancel": {
            if (speechService == null) {
              throw new SpeechServiceNotFound();
            }
            result.success(speechService.cancel());
          }
          break;

          case "speechService.destroy": {
            if (speechService == null) {
              throw new SpeechServiceNotFound();
            }
            speechService.shutdown();
            speechService = null;
            if (speechServiceRecognizer != null) {
              speechServiceRecognizer.speechServiceOwned = false;
              speechServiceRecognizer = null;
            }
            result.success(null);
          }
          break;

          default:
            result.notImplemented();
            break;
        }
      } catch (WrongArgumentTypeException error) {
        result.error("WRONG_TYPE", "Wrong argument type", error);
      } catch (SpeechServiceNotFound error) {
        result.error(
            "NO_SPEECH_SERVICE",
            "Speech service not created.",
            error);
      }
    }
  }

  private void handleSpeechServiceInit(MethodCall call, Result result) {
    try {
      final Map<String, Object> argsMap =
          castMethodCallArgs(call, argsMapClass);
      final Integer recognizerId = getRequiredArgumentFromMap(
          argsMap, "recognizerId", Integer.class);
      final Integer sampleRate = getRequiredArgumentFromMap(
          argsMap, "sampleRate", Integer.class);

      synchronized (lifecycleLock) {
        if (!attached || recognizerScheduler == null) {
          result.error("PLUGIN_DETACHED", "Vosk plugin is detached", null);
          return;
        }
        if (speechService != null || speechServiceRecognizer != null) {
          result.error(
              "INITIALIZE_FAIL",
              "SpeechService instance already exist or initialization is pending.",
              null);
          return;
        }
        final ManagedRecognizer handle = getRecognizerByIdLocked(recognizerId);
        handle.speechServiceOwned = true;
        speechServiceRecognizer = handle;
        final RecognizerTaskScheduler scheduler = recognizerScheduler;
        final int generation = engineGeneration;
        final boolean accepted = scheduler.submit(
            handle.id,
            handle.lane,
            "speechService.init",
            () -> new SpeechService(handle.recognizer, sampleRate),
            new RecognizerTaskScheduler.Callback<SpeechService>() {
              @Override
              public void onSuccess(SpeechService createdService) {
                boolean installed = false;
                synchronized (lifecycleLock) {
                  if (attached
                      && generation == engineGeneration
                      && speechService == null
                      && speechServiceRecognizer == handle) {
                    speechService = createdService;
                    installed = true;
                  }
                }
                if (!installed) {
                  synchronized (lifecycleLock) {
                    if (speechServiceRecognizer == handle) {
                      speechServiceRecognizer = null;
                    }
                    handle.speechServiceOwned = false;
                  }
                  try {
                    createdService.shutdown();
                  } catch (RuntimeException error) {
                    Log.w(TAG, "Failed to discard SpeechService", error);
                  }
                  return;
                }
                postResultSuccess(generation, result, null);
              }

              @Override
              public void onError(Exception error) {
                synchronized (lifecycleLock) {
                  if (speechServiceRecognizer == handle) {
                    speechServiceRecognizer = null;
                  }
                  handle.speechServiceOwned = false;
                }
                postResultError(
                    generation,
                    result,
                    handle,
                    "speechService.init",
                    error);
              }
            });
        if (!accepted) {
          if (speechServiceRecognizer == handle) {
            speechServiceRecognizer = null;
          }
          handle.speechServiceOwned = false;
        }
      }
    } catch (MissingRequiredArgument error) {
      result.error(
          "MISSING_REQUIRED_ARGUMENT",
          "Couldn't find required argument",
          error);
    } catch (WrongArgumentTypeException error) {
      result.error("WRONG_TYPE", "Wrong argument type", error);
    } catch (RecognizerNotFound error) {
      result.error(
          "NO_RECOGNIZER",
          "There is no recognizer with this id.",
          error);
    }
  }

  private void handleRecognizerMethod(MethodCall call, Result result) {
    try {
      final Map<String, Object> argsMap =
          castMethodCallArgs(call, argsMapClass);
      if ("recognizer.create".equals(call.method)) {
        handleRecognizerCreate(argsMap, result);
        return;
      }
      final Integer recognizerId = getRequiredArgumentFromMap(
          argsMap, "recognizerId", Integer.class);

      synchronized (lifecycleLock) {
        if (!attached || recognizerScheduler == null) {
          result.error("PLUGIN_DETACHED", "Vosk plugin is detached", null);
          return;
        }

        final ManagedRecognizer handle = getRecognizerByIdLocked(recognizerId);
        if (handle.speechServiceOwned) {
          result.error(
              "RECOGNIZER_BUSY",
              "Recognizer is owned by SpeechService",
              recognizerId);
          return;
        }

        switch (call.method) {
          case "recognizer.setSpeakerModel": {
            final String speakerModelPath = getRequiredArgumentFromMap(
                argsMap, "speakerModelPath", String.class);
            final SpeakerModel speakerModel =
                speakerModelsMap.get(speakerModelPath);
            if (speakerModel == null) {
              result.error(
                  "NO_SPEAKER_MODEL",
                  "Couldn't find speaker model with this path. Pls, create speaker model or send correct path.",
                  null);
              return;
            }
            submitRecognizerOperationLocked(
                handle,
                "setSpeakerModel",
                () -> {
                  handle.recognizer.setSpeakerModel(speakerModel);
                  return null;
                },
                result);
            return;
          }

          case "recognizer.setMaxAlternatives": {
            final Integer maxAlternatives = getRequiredArgumentFromMap(
                argsMap, "maxAlternatives", Integer.class);
            submitRecognizerOperationLocked(
                handle,
                "setMaxAlternatives",
                () -> {
                  handle.recognizer.setMaxAlternatives(maxAlternatives);
                  return null;
                },
                result);
            return;
          }

          case "recognizer.setWords": {
            final Boolean words = getRequiredArgumentFromMap(
                argsMap, "words", Boolean.class);
            submitRecognizerOperationLocked(
                handle,
                "setWords",
                () -> {
                  handle.recognizer.setWords(words);
                  return null;
                },
                result);
            return;
          }

          case "recognizer.setPartialWords": {
            final Boolean partialWords = getRequiredArgumentFromMap(
                argsMap, "partialWords", Boolean.class);
            submitRecognizerOperationLocked(
                handle,
                "setPartialWords",
                () -> {
                  handle.recognizer.setPartialWords(partialWords);
                  return null;
                },
                result);
            return;
          }

          case "recognizer.acceptWaveForm": {
            final byte[] bytesArgument = getArgumentFromMap(
                argsMap, "bytes", byte[].class);
            final float[] floatsArgument = getArgumentFromMap(
                argsMap, "floats", float[].class);
            if (bytesArgument == null && floatsArgument == null) {
              result.error(
                  "WRONG_ARGS",
                  "Didn't find data. Pls, send data",
                  null);
              return;
            }
            final byte[] bytes =
                bytesArgument == null ? null : bytesArgument.clone();
            final float[] floats =
                floatsArgument == null ? null : floatsArgument.clone();
            submitRecognizerOperationLocked(
                handle,
                "acceptWaveForm",
                () -> {
                  final long startedAt = SystemClock.elapsedRealtime();
                  final boolean accepted = bytes == null
                      ? handle.recognizer.acceptWaveForm(floats, floats.length)
                      : handle.recognizer.acceptWaveForm(bytes, bytes.length);
                  final long nativeMs =
                      SystemClock.elapsedRealtime() - startedAt;
                  if (nativeMs >= 150L) {
                    Log.w(
                        TAG,
                        "slow acceptWaveForm recognizerId="
                            + recognizerId
                            + " lane="
                            + handle.lane.wireName()
                            + " bytes="
                            + (bytes == null ? 0 : bytes.length)
                            + " floats="
                            + (floats == null ? 0 : floats.length)
                            + " nativeMs="
                            + nativeMs
                            + " thread="
                            + Thread.currentThread().getName());
                  }
                  return accepted;
                },
                result);
            return;
          }

          case "recognizer.getResult":
            submitRecognizerOperationLocked(
                handle,
                "getResult",
                () -> handle.recognizer.getResult(),
                result);
            return;

          case "recognizer.getPartialResult":
            submitRecognizerOperationLocked(
                handle,
                "getPartialResult",
                () -> handle.recognizer.getPartialResult(),
                result);
            return;

          case "recognizer.getFinalResult":
            submitRecognizerOperationLocked(
                handle,
                "getFinalResult",
                () -> handle.recognizer.getFinalResult(),
                result);
            return;

          case "recognizer.setGrammar": {
            final String grammar = getRequiredArgumentFromMap(
                argsMap, "grammar", String.class);
            final RecognizerTaskScheduler.Lane previousLane = handle.lane;
            handle.lane = handle.lane.promotedByGrammar(grammar);
            if (previousLane != handle.lane) {
              Log.i(
                  TAG,
                  "[VOSK_SCHEDULER] stage=lane_promoted recognizerId="
                      + recognizerId
                      + " from="
                      + previousLane.wireName()
                      + " to="
                      + handle.lane.wireName());
            }
            submitRecognizerOperationLocked(
                handle,
                "setGrammar",
                () -> {
                  handle.recognizer.setGrammar(grammar);
                  return null;
                },
                result);
            return;
          }

          case "recognizer.reset":
            submitRecognizerOperationLocked(
                handle,
                "reset",
                () -> {
                  handle.recognizer.reset();
                  return null;
                },
                result);
            return;

          case "recognizer.close":
            submitRecognizerCloseLocked(handle, result);
            return;

          default:
            result.notImplemented();
        }
      }
    } catch (MissingRequiredArgument error) {
      result.error(
          "MISSING_REQUIRED_ARGUMENT",
          "Couldn't find required argument",
          error);
    } catch (WrongArgumentTypeException error) {
      result.error("WRONG_TYPE", "Wrong argument type", error);
    } catch (RecognizerNotFound error) {
      result.error(
          "NO_RECOGNIZER",
          "There is no recognizer with this id.",
          error);
    }
  }

  private void handleRecognizerCreate(
      Map<String, Object> argsMap,
      Result result)
      throws MissingRequiredArgument, WrongArgumentTypeException {
    final Integer sampleRate = getRequiredArgumentFromMap(
        argsMap, "sampleRate", Integer.class);
    final String modelPath = getRequiredArgumentFromMap(
        argsMap, "modelPath", String.class);
    final String grammar = getArgumentFromMap(
        argsMap, "grammar", String.class);
    final String requestedLane = getArgumentFromMap(
        argsMap, "taskLane", String.class);

    synchronized (lifecycleLock) {
      if (!attached || recognizerScheduler == null) {
        result.error("PLUGIN_DETACHED", "Vosk plugin is detached", null);
        return;
      }
      final Model model = modelsMap.get(modelPath);
      if (model == null) {
        result.error(
            "NO_MODEL",
            "Couldn't find model with this path. Pls, create model or send correct path.",
            null);
        return;
      }
      final int recognizerId = nextRecognizerId++;
      final RecognizerTaskScheduler.Lane lane = initialLaneLocked(
          requestedLane,
          grammar);
      final RecognizerTaskScheduler scheduler = recognizerScheduler;
      final int generation = engineGeneration;
      scheduler.submit(
          recognizerId,
          lane,
          "create",
          () -> grammar == null
              ? new Recognizer(model, sampleRate)
              : new Recognizer(model, sampleRate, grammar),
          new RecognizerTaskScheduler.Callback<Recognizer>() {
            @Override
            public void onSuccess(Recognizer recognizer) {
              final ManagedRecognizer handle =
                  new ManagedRecognizer(recognizerId, recognizer, lane);
              boolean installed = false;
              synchronized (lifecycleLock) {
                if (attached && generation == engineGeneration) {
                  recognizersMap.put(recognizerId, handle);
                  installed = true;
                }
              }
              if (!installed) {
                handle.closeIfNeeded();
                Log.i(
                    TAG,
                    "[VOSK_SCHEDULER] stage=create_discarded recognizerId="
                        + recognizerId
                        + " lane="
                        + lane.wireName()
                        + " reason=detached");
                return;
              }
              Log.i(
                  TAG,
                  "[VOSK_SCHEDULER] stage=recognizer_created recognizerId="
                      + recognizerId
                      + " lane="
                      + lane.wireName()
                      + " grammarPresent="
                      + (grammar != null));
              postResultSuccess(generation, result, recognizerId);
            }

            @Override
            public void onError(Exception error) {
              final ManagedRecognizer placeholder =
                  new ManagedRecognizer(recognizerId, null, lane);
              postResultError(
                  generation,
                  result,
                  placeholder,
                  "create",
                  error);
            }
          });
    }
  }

  private RecognizerTaskScheduler.Lane initialLaneLocked(
      String requestedLane,
      String grammar) {
    final RecognizerTaskScheduler.Lane explicit =
        RecognizerTaskScheduler.Lane.forRecognizer(requestedLane, grammar);
    if (requestedLane != null || grammar != null) {
      return explicit;
    }
    for (ManagedRecognizer handle : recognizersMap.values()) {
      if (handle.lane == RecognizerTaskScheduler.Lane.COMMAND
          && !handle.closing
          && !handle.closed) {
        return RecognizerTaskScheduler.Lane.FREE_TEXT;
      }
    }
    return RecognizerTaskScheduler.Lane.DEFAULT;
  }

  private <T> void submitRecognizerOperationLocked(
      ManagedRecognizer handle,
      String operation,
      Callable<T> callable,
      Result result) {
    final RecognizerTaskScheduler scheduler = recognizerScheduler;
    if (scheduler == null) {
      result.error("PLUGIN_DETACHED", "Vosk plugin is detached", null);
      return;
    }
    final int generation = engineGeneration;
    final RecognizerTaskScheduler.Lane lane = handle.lane;
    scheduler.submit(
        handle.id,
        lane,
        operation,
        callable,
        new RecognizerTaskScheduler.Callback<T>() {
          @Override
          public void onSuccess(T value) {
            postResultSuccess(generation, result, value);
          }

          @Override
          public void onError(Exception error) {
            postResultError(
                generation,
                result,
                handle,
                operation,
                error);
          }
        });
  }

  private void submitRecognizerCloseLocked(
      ManagedRecognizer handle,
      Result result) {
    if (handle.closing) {
      result.error(
          "NO_RECOGNIZER",
          "Recognizer is already closing",
          handle.id);
      return;
    }
    handle.closing = true;
    final RecognizerTaskScheduler scheduler = recognizerScheduler;
    if (scheduler == null) {
      handle.closing = false;
      result.error("PLUGIN_DETACHED", "Vosk plugin is detached", null);
      return;
    }
    final int generation = engineGeneration;
    scheduler.submit(
        handle.id,
        handle.lane,
        "close",
        () -> {
          handle.closeIfNeeded();
          return null;
        },
        new RecognizerTaskScheduler.Callback<Void>() {
          @Override
          public void onSuccess(Void value) {
            synchronized (lifecycleLock) {
              if (recognizersMap.get(handle.id) == handle) {
                recognizersMap.remove(handle.id);
              }
            }
            postResultSuccess(generation, result, null);
          }

          @Override
          public void onError(Exception error) {
            synchronized (lifecycleLock) {
              if (attached && generation == engineGeneration) {
                handle.closing = false;
              }
            }
            postResultError(generation, result, handle, "close", error);
          }
        });
  }

  private void postResultSuccess(
      int generation,
      Result result,
      Object value) {
    mainHandler.post(() -> {
      synchronized (lifecycleLock) {
        if (!attached || generation != engineGeneration) {
          Log.i(
              TAG,
              "[VOSK_SCHEDULER] stage=result_dropped reason=detached "
                  + "generation="
                  + generation
                  + " currentGeneration="
                  + engineGeneration);
          return;
        }
      }
      result.success(value);
    });
  }

  private void postResultError(
      int generation,
      Result result,
      ManagedRecognizer handle,
      String operation,
      Exception error) {
    mainHandler.post(() -> {
      synchronized (lifecycleLock) {
        if (!attached || generation != engineGeneration) {
          Log.i(
              TAG,
              "[VOSK_SCHEDULER] stage=error_dropped reason=detached "
                  + "recognizerId="
                  + handle.id
                  + " operation="
                  + operation
                  + " error="
                  + error);
          return;
        }
      }
      final boolean cancelled =
          error instanceof RecognizerTaskScheduler.TaskCancelledException
              || error instanceof RecognizerTaskScheduler.SchedulerClosedException;
      final String code = cancelled
          ? "RECOGNIZER_OPERATION_CANCELLED"
          : "RECOGNIZER_OPERATION_FAILED";
      final HashMap<String, Object> details = new HashMap<>();
      details.put("recognizerId", handle.id);
      details.put("lane", handle.lane.wireName());
      details.put("operation", operation);
      details.put("errorType", error.getClass().getSimpleName());
      Log.w(
          TAG,
          "[VOSK_SCHEDULER] stage=operation_failed recognizerId="
              + handle.id
              + " lane="
              + handle.lane.wireName()
              + " operation="
              + operation
              + " cancelled="
              + cancelled
              + " error="
              + error);
      result.error(code, error.getMessage(), details);
    });
  }

  private void postChannelMethod(
      int generation,
      String method,
      Object arguments) {
    mainHandler.post(() -> {
      final MethodChannel currentChannel;
      synchronized (lifecycleLock) {
        if (!attached || generation != engineGeneration || channel == null) {
          return;
        }
        currentChannel = channel;
      }
      currentChannel.invokeMethod(method, arguments);
    });
  }

  public <T> T castMethodCallArgs(MethodCall call, Class<T> classType)
      throws WrongArgumentTypeException {
    if (classType.isInstance(call.arguments)) {
      return classType.cast(call.arguments);
    }
    final Class<?> actual =
        call.arguments == null ? Object.class : call.arguments.getClass();
    throw new WrongArgumentTypeException(
        actual,
        classType,
        String.format("%s method", call.method));
  }

  public <T> T getArgumentFromMap(
      Map<String, Object> map,
      String argumentName,
      Class<T> classType) throws WrongArgumentTypeException {
    final Object argument = map.get(argumentName);
    if (argument == null) {
      return null;
    }
    if (classType.isInstance(argument)) {
      return classType.cast(argument);
    }
    throw new WrongArgumentTypeException(
        argument.getClass(),
        classType,
        String.format("Argument %s", argumentName));
  }

  public <T> T getRequiredArgumentFromMap(
      Map<String, Object> map,
      String argumentName,
      Class<T> classType)
      throws MissingRequiredArgument, WrongArgumentTypeException {
    final T argument = getArgumentFromMap(map, argumentName, classType);
    if (argument == null) {
      throw new MissingRequiredArgument(argumentName);
    }
    return argument;
  }

  private ManagedRecognizer getRecognizerByIdLocked(Integer recognizerId)
      throws RecognizerNotFound {
    final ManagedRecognizer handle = recognizersMap.get(recognizerId);
    if (handle == null || handle.closing || handle.closed) {
      throw new RecognizerNotFound(recognizerId);
    }
    return handle;
  }

  @Override
  public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
    final RecognizerTaskScheduler scheduler;
    final List<ManagedRecognizer> recognizers;
    final List<Model> models;
    final List<SpeakerModel> speakerModels;
    final SpeechService detachedSpeechService;
    final FlutterRecognitionListener detachedListener;
    final int detachedGeneration;

    synchronized (lifecycleLock) {
      if (!attached) {
        return;
      }
      detachedGeneration = engineGeneration;
      attached = false;
      engineGeneration++;
      if (channel != null) {
        channel.setMethodCallHandler(null);
      }
      channel = null;

      scheduler = recognizerScheduler;
      recognizerScheduler = null;

      recognizers = new ArrayList<>(recognizersMap.values());
      recognizersMap.clear();
      models = new ArrayList<>(modelsMap.values());
      modelsMap.clear();
      speakerModels = new ArrayList<>(speakerModelsMap.values());
      speakerModelsMap.clear();

      detachedSpeechService = speechService;
      speechService = null;
      speechServiceRecognizer = null;
      detachedListener = recognitionListener;
      recognitionListener = null;
    }

    final Runnable cleanup = () -> {
      if (detachedSpeechService != null) {
        try {
          detachedSpeechService.shutdown();
        } catch (RuntimeException error) {
          Log.w(TAG, "Failed to shut down SpeechService", error);
        }
      }
      if (detachedListener != null) {
        try {
          detachedListener.dispose();
        } catch (RuntimeException error) {
          Log.w(TAG, "Failed to dispose recognition listener", error);
        }
      }
      for (ManagedRecognizer handle : recognizers) {
        try {
          handle.closeIfNeeded();
        } catch (RuntimeException error) {
          Log.w(
              TAG,
              "Failed to close recognizerId=" + handle.id,
              error);
        }
      }
      for (Model model : models) {
        try {
          model.close();
        } catch (RuntimeException error) {
          Log.w(TAG, "Failed to close model", error);
        }
      }
      for (SpeakerModel speakerModel : speakerModels) {
        try {
          speakerModel.close();
        } catch (RuntimeException error) {
          Log.w(TAG, "Failed to close speaker model", error);
        }
      }
      Log.i(
          TAG,
          "[VOSK_SCHEDULER] stage=detach_cleanup_done generation="
              + detachedGeneration
              + " recognizers="
              + recognizers.size());
    };

    final long startedAt = SystemClock.elapsedRealtime();
    final boolean completed = scheduler == null
        ? runCleanupSynchronously(cleanup)
        : scheduler.shutdownAfterCurrent(
            cleanup,
            DETACH_SCHEDULER_TIMEOUT_MS);
    Log.i(
        TAG,
        "[VOSK_SCHEDULER] stage=detached generation="
            + detachedGeneration
            + " completed="
            + completed
            + " waitMs="
            + (SystemClock.elapsedRealtime() - startedAt));
  }

  private boolean runCleanupSynchronously(Runnable cleanup) {
    cleanup.run();
    return true;
  }

  private static final class ManagedRecognizer {
    final int id;
    final Recognizer recognizer;
    volatile RecognizerTaskScheduler.Lane lane;
    volatile boolean closing;
    volatile boolean closed;
    volatile boolean speechServiceOwned;

    ManagedRecognizer(
        int id,
        Recognizer recognizer,
        RecognizerTaskScheduler.Lane lane) {
      this.id = id;
      this.recognizer = recognizer;
      this.lane = lane;
    }

    synchronized void closeIfNeeded() {
      if (closed) {
        return;
      }
      if (recognizer != null) {
        recognizer.close();
      }
      closed = true;
      closing = true;
    }
  }
}
