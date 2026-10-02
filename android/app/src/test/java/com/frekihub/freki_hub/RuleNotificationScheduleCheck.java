package com.frekihub.freki_hub;

import java.time.Instant;
import java.util.TimeZone;

/** Standalone JVM check of production clock calculation; no device or APK required. */
public final class RuleNotificationScheduleCheck {
    private static void next(String zone, String time, String after, String expected) {
        TimeZone.setDefault(TimeZone.getTimeZone(zone));
        long actual = RuleNotifications.INSTANCE.nextTime(time, Instant.parse(after).toEpochMilli());
        if (actual != Instant.parse(expected).toEpochMilli()) {
            throw new AssertionError(zone + " " + time + ": " + Instant.ofEpochMilli(actual) + " != " + expected);
        }
    }

    public static void main(String[] args) {
        TimeZone original = TimeZone.getDefault();
        try {
            next("Asia/Manila", "08:00", "2026-10-01T23:59:00Z", "2026-10-02T00:00:00Z");
            next("Asia/Manila", "08:00", "2026-10-02T00:00:00Z", "2026-10-03T00:00:00Z");
            next("Asia/Manila", "00:00", "2026-12-31T15:59:00Z", "2026-12-31T16:00:00Z");
            next("America/New_York", "08:00", "2026-03-07T13:00:00Z", "2026-03-08T12:00:00Z");
            next("America/New_York", "02:30", "2026-03-08T08:00:00Z", "2026-03-09T06:30:00Z");
            next("America/New_York", "08:00", "2026-10-31T12:00:00Z", "2026-11-01T13:00:00Z");
            System.out.println("6 notification clock checks passed");
        } finally {
            TimeZone.setDefault(original);
        }
    }
}
