-- Samgeet server, schema 2.1 (admin panel 2): run once in phpMyAdmin (open the database -> SQL tab ->
-- paste -> Go). Running it a second time only says "Duplicate column"; nothing breaks.
--
-- source     where a message was sent from: the web panel or the admin tools in the app
-- follow_up  a re-send that only goes to part of an earlier message's audience:
--            'missed' = phones that never got it, 'unopened' = phones that got it but didn't open it
-- follow_of  the earlier message it follows up

ALTER TABLE notifications
  ADD COLUMN source    ENUM('web','app') NOT NULL DEFAULT 'web' AFTER created_by,
  ADD COLUMN follow_up ENUM('missed','unopened') NULL AFTER source,
  ADD COLUMN follow_of INT UNSIGNED NULL AFTER follow_up,
  ADD KEY idx_notifications_follow (follow_of);
