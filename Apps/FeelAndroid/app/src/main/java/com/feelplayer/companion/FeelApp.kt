// Feel Player
// Copyright (C) 2026 7 Angle. All rights reserved.

package com.feelplayer.companion

import android.app.Application
import com.feedbackjar.sdk.FeedbackJar

class FeelApp : Application() {
    override fun onCreate() {
        super.onCreate()
        FeedbackJar.init(this, "cmw66df8p003wcwp04bsof78i")
    }
}
