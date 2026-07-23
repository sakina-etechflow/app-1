# R8 keep rules for the release build.
#
# Without these the app crashes on launch in every release build, before Flutter
# starts: androidx.startup.InitializationProvider -> WorkManagerInitializer ->
# "Failed to create an instance of androidx.work.impl.WorkDatabase". Debug builds
# are not minified, so the crash is invisible until you install a release APK.

# --- Room / WorkManager ------------------------------------------------------
# ML Kit pulls in WorkManager transitively (model download scheduling), and
# WorkManager persists its state in a Room database. Room resolves its generated
# *_Impl classes by reflection, so R8 must keep both the classes and their
# no-arg constructors or the lookup fails at runtime.
-keep class * extends androidx.room.RoomDatabase { <init>(); }
-keepclassmembers class * extends androidx.room.RoomDatabase { public <init>(); }
-keep class androidx.work.impl.WorkDatabase_Impl { <init>(); }
-dontwarn androidx.room.paging.**

# androidx.startup discovers initializers reflectively from the merged manifest.
-keep class * implements androidx.startup.Initializer { <init>(); }
-keep class androidx.startup.InitializationProvider { *; }

# Workers are instantiated reflectively by WorkManager.
-keep class * extends androidx.work.ListenableWorker { <init>(...); }

# --- ML Kit ------------------------------------------------------------------
# Face detection and selfie segmentation load their models through reflection.
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_** { *; }
-dontwarn com.google.mlkit.**
