/*
 * 測試用的固定時鐘 —— 只給 `node --require` 預載到**子程序**用，production 工具不引用它。
 *
 * 為什麼需要：`tools/backup-settings.js` 的備份檔名帶「到秒」的時間戳，所以
 * 「同一秒重跑會撞名」這條守衛，先前只能靠「預先建好未來幾秒的候選檔名」去賭時鐘——
 * 排程延遲或時鐘跳動就會落出視窗，而且工具若因回歸而忽略撞名 exit 0，會被歸成 SKIP
 * 而不是 FAIL（＝把沒驗到包成綠燈）。
 *
 * 把時鐘固定住之後，撞名變成**確定性**觸發：測試只要預建那唯一一個檔名即可。
 * 這是「不在 production 工具裡開測試專用注入點」的做法——注入發生在子程序的
 * module loader 層，受測程式碼一個字都不用改。
 *
 * 用法：
 *   FIXED_CLOCK_MS=<epoch ms> node --require tests/helpers/fixed-clock.js <script>
 */
"use strict";

const FIXED = Number(process.env.FIXED_CLOCK_MS);
if (!Number.isFinite(FIXED)) {
  // 大聲失敗，不要靜默退回真實時鐘——那會讓「注入成功了嗎」變成無法回答的問題。
  throw new Error("fixed-clock：FIXED_CLOCK_MS 未設或不是數字，拒絕以真實時鐘執行");
}

const RealDate = Date;
class FrozenDate extends RealDate {
  constructor(...args) {
    if (args.length === 0) {
      super(FIXED);
    } else {
      super(...args);
    }
  }
  static now() {
    return FIXED;
  }
}
global.Date = FrozenDate;
