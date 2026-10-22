# The ID reader (paddle_ocr_native: ONNX Runtime + OpenCV, 22 Oct 2026) calls into native code by name
# (JNI), so R8 must not rename or strip these.
-keep class ai.onnxruntime.** { *; }
-keep class org.opencv.** { *; }
-keep class com.paddle.ocr.** { *; }
-keep class com.flespark.paddle_ocr_native.** { *; }
