package com.example.sign_bridge

import android.os.Bundle
import androidx.appcompat.app.AppCompatActivity

class CameraActivity : AppCompatActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        // Set the theme before calling super.onCreate()
        setTheme(androidx.appcompat.R.style.Theme_AppCompat_Light)
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_camera)

        // Only add the fragment if it hasn't been added already
        if (savedInstanceState == null) {
            supportFragmentManager.beginTransaction()
                .replace(R.id.camera_fragment_container, com.example.sign_bridge.fragment.CameraFragment())
                .commitNow()
        }
    }
}
