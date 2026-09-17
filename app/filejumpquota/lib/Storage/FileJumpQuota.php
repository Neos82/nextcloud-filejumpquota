<?php

declare(strict_types=1);

namespace OCA\FileJumpQuota\Storage;

use OC\Files\Storage\Wrapper\Wrapper;
use OCP\Files\NotEnoughSpaceException;
use OCP\Files\Storage\IStorage;

class FileJumpQuota extends Wrapper {
    private int $quota;

    public function __construct(array $parameters) {
        parent::__construct($parameters);

        // Quota predefinita: 100 GiB
        $this->quota = (int)($parameters["quota"] ?? 0);
    }

    private function usedSpace(): int {
        $cache = $this->getWrapperStorage()->getCache();
        $entry = $cache->get("");

        if ($entry && isset($entry["size"]) && $entry["size"] >= 0) {
            return (int)$entry["size"];
        }

        return 0;
    }

    private function existingSize(string $path): int {
        $cache = $this->getWrapperStorage()->getCache();
        $entry = $cache->get($path);

        if ($entry && isset($entry["size"]) && $entry["size"] >= 0) {
            return (int)$entry["size"];
        }

        return 0;
    }

    public function free_space(string $path): int|float|false {
        $backendFree = $this->getWrapperStorage()->free_space($path);

        // Se sovrascriviamo un file, il suo spazio attuale è recuperabile.
        $used = max(0, $this->usedSpace() - $this->existingSize($path));
        $quotaFree = max(0, $this->quota - $used);

        if (is_int($backendFree) || is_float($backendFree)) {
            if ($backendFree >= 0) {
                return min($backendFree, $quotaFree);
            }
        }

        return $quotaFree;
    }

    public function file_put_contents(string $path, mixed $data): int|float|false {
        $free = $this->free_space($path);
        $length = strlen($data);

        if ($free !== false && $free >= 0 && $length > $free) {
            return false;
        }

        return $this->getWrapperStorage()->file_put_contents($path, $data);
    }

    public function fopen(string $path, string $mode) {
        if ($mode === "r" || $mode === "rb") {
            return $this->getWrapperStorage()->fopen($path, $mode);
        }

        $free = $this->free_space($path);

        if ($free !== false && $free <= 0) {
            return false;
        }

        $stream = $this->getWrapperStorage()->fopen($path, $mode);

        if (
            $stream &&
            (is_int($free) || is_float($free)) &&
            $free >= 0
        ) {
            return \OC\Files\Stream\Quota::wrap($stream, $free);
        }

        return $stream;
    }

    public function writeStream(string $path, $stream, ?int $size = null): int {
        $free = $this->free_space($path);

        if ($free !== false && $free <= 0) {
            throw new NotEnoughSpaceException();
        }

        if (
            $size !== null &&
            $free !== false &&
            $free >= 0 &&
            $size > $free
        ) {
            throw new NotEnoughSpaceException();
        }

        if ($size !== null) {
            return parent::writeStream($path, $stream, $size);
        }

        return parent::writeStreamFallback($path, $stream);
    }

    public function copy(string $source, string $target): bool {
        $size = $this->getWrapperStorage()->filesize($source);
        $free = $this->free_space($target);

        if (
            $size !== false &&
            $free !== false &&
            $free >= 0 &&
            $size > $free
        ) {
            return false;
        }

        return $this->getWrapperStorage()->copy($source, $target);
    }

    public function copyFromStorage(
        IStorage $sourceStorage,
        string $sourceInternalPath,
        string $targetInternalPath
    ): bool {
        $size = $sourceStorage->filesize($sourceInternalPath);
        $free = $this->free_space($targetInternalPath);

        if (
            $size !== false &&
            $free !== false &&
            $free >= 0 &&
            $size > $free
        ) {
            return false;
        }

        return $this->getWrapperStorage()->copyFromStorage(
            $sourceStorage,
            $sourceInternalPath,
            $targetInternalPath
        );
    }

    public function moveFromStorage(
        IStorage $sourceStorage,
        string $sourceInternalPath,
        string $targetInternalPath
    ): bool {
        $size = $sourceStorage->filesize($sourceInternalPath);
        $free = $this->free_space($targetInternalPath);

        if (
            $size !== false &&
            $free !== false &&
            $free >= 0 &&
            $size > $free
        ) {
            return false;
        }

        return $this->getWrapperStorage()->moveFromStorage(
            $sourceStorage,
            $sourceInternalPath,
            $targetInternalPath
        );
    }
}
