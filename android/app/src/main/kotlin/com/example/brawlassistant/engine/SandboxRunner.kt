package com.example.brawlassistant.engine

import android.content.Context
import androidx.javascriptengine.JavaScriptIsolate
import androidx.javascriptengine.JavaScriptSandbox
import com.example.brawlassistant.core.EngineException
import com.example.brawlassistant.core.ScriptRunner
import kotlinx.coroutines.guava.await

/**
 * androidx.javascriptengine(JavaScriptSandbox) 로 engine/draft-engine.js 를 실행하는 실행기.
 * WebView 의 V8 을 별도 샌드박스 프로세스에서 쓴다 (웹과 같은 엔진 계열). 앱 프로세스에 JS 엔진을 넣지 않는다.
 */
class SandboxRunner private constructor(private val sandbox: JavaScriptSandbox, private val isolate: JavaScriptIsolate) : ScriptRunner, AutoCloseable {
    override suspend fun eval(code: String): String = isolate.evaluateJavaScriptAsync(code).await()

    override fun close() {
        runCatching { isolate.close() }
        runCatching { sandbox.close() }
    }

    companion object {
        /** 이 기기의 Android System WebView 가 JavaScriptSandbox 를 지원하는지 */
        fun isSupported(): Boolean = JavaScriptSandbox.isSupported()

        suspend fun create(context: Context): SandboxRunner {
            if (!isSupported()) throw EngineException("이 기기의 Android System WebView 가 JavaScript 엔진(JavaScriptSandbox)을 지원하지 않습니다. Play 스토어에서 Android System WebView 를 업데이트하세요.")
            val sandbox = JavaScriptSandbox.createConnectedInstanceAsync(context.applicationContext).await()
            return SandboxRunner(sandbox, sandbox.createIsolate())
        }
    }
}
