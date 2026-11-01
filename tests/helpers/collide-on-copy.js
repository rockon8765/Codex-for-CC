/*
 * 測試用的「複製階段撞名」注入 —— 只給 `node --require` 預載到**子程序**用，production 工具不引用它。
 *
 * 為什麼需要：`tools/backup-settings.js` 的預檢擋得住已存在的備份，所以要測
 * 「預檢通過後才被別的程序搶先建立」，必須把目的檔建在預檢與 `copyFileSync` 之間。
 * 這裡在呼叫真正的 `copyFileSync` 之前，先替目標路徑含指定字串的那次複製建出佔位檔。
 *
 * 用法：
 *   COLLIDE_ON_COPY=<目的路徑片段> node --require tests/helpers/collide-on-copy.js <script>
 */
"use strict";

const fs = require("fs");

const NEEDLE = process.env.COLLIDE_ON_COPY;
if (!NEEDLE) {
  // 大聲失敗：注入沒生效時若照常執行，「撞名案」就只是一般成功路徑。
  throw new Error("collide-on-copy：COLLIDE_ON_COPY 未設，拒絕執行");
}

const realCopy = fs.copyFileSync;
fs.copyFileSync = function (src, dest, mode) {
  if (String(dest).includes(NEEDLE)) fs.writeFileSync(dest, "別的程序的備份");
  return realCopy.call(fs, src, dest, mode);
};
