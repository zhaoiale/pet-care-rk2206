import { notificationManager } from '@kit.NotificationKit';

const NOTIFICATION_ID = 1001;
const MIN_INTERVAL_MS = 5 * 60 * 1000;
let lastNotifyTime = 0;
let anxietyWasHigh = false;

const THRESHOLD = 70;

export function checkAndNotifyAnxiety(anxietyLevel: number): void {
  if (anxietyLevel > THRESHOLD) {
    if (!anxietyWasHigh) {
      const now = Date.now();
      if (now - lastNotifyTime > MIN_INTERVAL_MS) {
        publishAnxietyAlert(anxietyLevel);
        lastNotifyTime = now;
      }
    }
    anxietyWasHigh = true;
  } else {
    anxietyWasHigh = false;
  }
}

function publishAnxietyAlert(anxietyLevel: number): void {
  try {
    const request: notificationManager.NotificationRequest = {
      id: NOTIFICATION_ID,
      content: {
        notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
        normal: {
          title: '宠物情绪预警',
          text: '情绪指数 ' + anxietyLevel.toString() + '，建议立即安抚！'
        }
      }
    };
    notificationManager.publish(request).then(() => {
      console.info('[Notification] Sent for Lv=' + anxietyLevel.toString());
    }).catch((err: Error) => {
      console.error('[Notification] Publish failed: ' + JSON.stringify(err));
    });
  } catch (err) {
    console.error('[Notification] Error: ' + JSON.stringify(err));
  }
}
