<?php
// Copy to config.php in this folder ON THE SERVER (.htaccess blocks it) and fill it in.
// Never commit the real file.
return [
    // The app signing key: 64 hex characters, the same value as SAMGEET_APP_KEY in the app's
    // secrets.json. Make one with:  php -r "echo bin2hex(random_bytes(32));"
    'app_key' => 'PUT_64_HEX_CHARACTERS_HERE',

    // Database. Leave these out to use the samgeet_config.php the first API already uses.
    // 'host' => 'localhost',
    // 'name' => 'YOUR_DATABASE_NAME',
    // 'user' => 'YOUR_DATABASE_USER',
    // 'pass' => 'YOUR_DATABASE_PASSWORD',
];
