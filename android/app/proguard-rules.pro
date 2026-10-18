# App-specific R8/ProGuard keep rules. Flutter's own rules are injected by the
# Flutter Gradle plugin; add rules here only when a release build or runtime
# verification demonstrates they are needed.

# shared_preferences_android 2.5.0 calls its Kotlin code through JNI, and
# package:jni looks these Kotlin classes up by name (the plugin's own generated
# classes are @Keep). Without them R8 renames e.g. Continuation, getAll's
# signature no longer matches, and startup throws NoSuchMethodError (0.5.1's
# splash-screen hang). Drop once jni ships these rules:
# https://github.com/dart-lang/native/issues/3732
# https://github.com/flutter/flutter/issues/194649
-keep class kotlin.Unit { *; }
-keep class kotlin.Result { *; }
-keep class kotlin.Result$Failure { *; }
-keep class kotlin.coroutines.Continuation { *; }
-keep class kotlin.coroutines.intrinsics.CoroutineSingletons { *; }
-keep class kotlin.coroutines.intrinsics.IntrinsicsKt { *; }
