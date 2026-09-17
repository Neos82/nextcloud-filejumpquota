<?php

declare(strict_types=1);

namespace OCA\FileJumpQuota\AppInfo;

use OCA\FileJumpQuota\Storage\FileJumpQuota;
use OCP\AppFramework\App;
use OCP\AppFramework\Bootstrap\IBootContext;
use OCP\AppFramework\Bootstrap\IBootstrap;
use OCP\AppFramework\Bootstrap\IRegistrationContext;
use OCP\Files\Storage\IStorage;
use OCP\IUserManager;
use OCP\Server;
use OCP\Util;

class Application extends App implements IBootstrap {
    public const APP_ID = "filejumpquota";

    public function __construct(array $urlParams = []) {
        parent::__construct(self::APP_ID, $urlParams);
    }

    public function register(IRegistrationContext $context): void {
        Util::connectHook(
            "OC_Filesystem",
            "preSetup",
            $this,
            "addStorageWrapper"
        );
    }

    public function boot(IBootContext $context): void {
    }

    public function addStorageWrapper(): void {
        \OC\Files\Filesystem::addStorageWrapper(
            "filejumpquota",
            [$this, "wrapStorage"],
            20
        );
    }

    public function wrapStorage(
        string $mountPoint,
        IStorage $storage
    ): IStorage {
        $normalized = "/" . trim($mountPoint, "/") . "/";

        if (!str_ends_with(
            $normalized,
            "/files/FileJump-Personale/"
        )) {
            return $storage;
        }

        /*
         * Mount previsto:
         * /USERID/files/FileJump-Personale/
         */
        if (!preg_match(
            '#^/([^/]+)/files/FileJump-Personale/$#',
            $normalized,
            $matches
        )) {
            return new FileJumpQuota([
                "storage" => $storage,
                "quota" => 0,
            ]);
        }

        $uid = $matches[1];

        $userManager = Server::get(IUserManager::class);
        $user = $userManager->get($uid);

        if ($user === null) {
            return new FileJumpQuota([
                "storage" => $storage,
                "quota" => 0,
            ]);
        }

        /*
         * Usa la quota reale assegnata all'utente Nextcloud.
         */
        $quota = $user->getQuotaBytes();

        /*
         * FAIL-CLOSED:
         * quota assente/non valida/unlimited -> quota zero.
         */
        if (!is_numeric($quota) || $quota <= 0) {
            $quota = 0;
        }

        return new FileJumpQuota([
            "storage" => $storage,
            "quota" => (int)$quota,
        ]);
    }
}
