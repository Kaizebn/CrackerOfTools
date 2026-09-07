import type { Activity } from '../db/types';

// Consecutive days (ending today or yesterday) with at least one activity.
export function computeStreak(activity: Activity[]): number {
  if (activity.length === 0) return 0;
  const days = new Set(activity.map((a) => a.date));
  let streak = 0;
  const cursor = new Date();
  // Allow the streak to still count if nothing done *yet* today but done yesterday.
  const todayStr = cursor.toISOString().slice(0, 10);
  if (!days.has(todayStr)) {
    cursor.setDate(cursor.getDate() - 1);
  }
  // Walk backwards while each day has activity.
  while (days.has(cursor.toISOString().slice(0, 10))) {
    streak += 1;
    cursor.setDate(cursor.getDate() - 1);
  }
  return streak;
}
