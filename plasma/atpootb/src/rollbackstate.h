// SPDX-License-Identifier: GPL-2.0-or-later
#pragma once

#include <QCryptographicHash>
#include <QDir>
#include <QFile>
#include <QFileDevice>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSaveFile>
#include <QDebug>
#include <QStringList>

namespace AtpRollback
{
inline QByteArray sha256(const QByteArray &contents)
{
    return QCryptographicHash::hash(contents, QCryptographicHash::Sha256).toHex();
}

inline int unixPermissions(QFileDevice::Permissions permissions)
{
    int mode = 0;
    if (permissions & QFileDevice::ReadOwner) mode |= 0400;
    if (permissions & QFileDevice::WriteOwner) mode |= 0200;
    if (permissions & QFileDevice::ExeOwner) mode |= 0100;
    if (permissions & QFileDevice::ReadGroup) mode |= 0040;
    if (permissions & QFileDevice::WriteGroup) mode |= 0020;
    if (permissions & QFileDevice::ExeGroup) mode |= 0010;
    if (permissions & QFileDevice::ReadOther) mode |= 0004;
    if (permissions & QFileDevice::WriteOther) mode |= 0002;
    if (permissions & QFileDevice::ExeOther) mode |= 0001;
    return mode;
}

inline bool writeManifest(const QString &path, const QJsonObject &root)
{
    const QFileInfo info(path);
    if (!QDir().mkpath(info.absolutePath())) {
        qWarning() << "Could not create rollback directory:" << info.absolutePath();
        return false;
    }

    QSaveFile file(path);
    if (!file.open(QIODevice::WriteOnly)) {
        qWarning() << "Could not open rollback manifest:" << path << file.errorString();
        return false;
    }

    const QByteArray contents = QJsonDocument(root).toJson(QJsonDocument::Compact);
    if (file.write(contents) != contents.size() || !file.commit()) {
        qWarning() << "Could not save rollback manifest:" << path << file.errorString();
        return false;
    }

    if (!QFile::setPermissions(path, QFileDevice::ReadOwner | QFileDevice::WriteOwner)) {
        qWarning() << "Could not restrict rollback snapshot permissions:" << path;
        QFile::remove(path);
        return false;
    }
    return true;
}

inline bool readManifest(const QString &path, QJsonObject *root)
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly)) {
        return false;
    }

    QJsonParseError error;
    const QJsonDocument document = QJsonDocument::fromJson(file.readAll(), &error);
    if (error.error != QJsonParseError::NoError || !document.isObject()) {
        qWarning() << "Invalid rollback manifest:" << path << error.errorString();
        return false;
    }

    *root = document.object();
    return true;
}

// Called before AeroThemePlasma changes a file. Existing snapshots are never
// overwritten: a later install must not replace the user's original state.
inline bool backupFiles(const QStringList &paths, const QString &manifestPath)
{
    if (QFileInfo::exists(manifestPath)) {
        QJsonObject existing;
        if (!readManifest(manifestPath, &existing)) {
            return false;
        }
        if (existing.value(QStringLiteral("restore_started")).toBool()) {
            qWarning() << "A previous rollback is incomplete; resolve it before applying AeroThemePlasma again.";
            return false;
        }
        return true;
    }

    QJsonArray entries;
    for (const QString &rawPath : paths) {
        const QString path = QDir::cleanPath(rawPath);
        const QFileInfo info(path);
        QJsonObject entry;
        entry.insert(QStringLiteral("path"), path);

        const bool isSymlink = info.isSymLink();
        const QString symlinkTarget = isSymlink ? info.canonicalFilePath() : QString();
        const QFileInfo targetInfo(symlinkTarget);
        if ((isSymlink && (!targetInfo.exists() || !targetInfo.isFile()))
            || (!isSymlink && info.exists() && !info.isFile())) {
            entry.insert(QStringLiteral("skipped"), true);
            entry.insert(QStringLiteral("reason"), QStringLiteral("not a regular file"));
            entries.append(entry);
            continue;
        }

        const bool existed = info.exists();
        entry.insert(QStringLiteral("is_symlink"), isSymlink);
        if (isSymlink) {
            entry.insert(QStringLiteral("symlink_target"), QDir::cleanPath(symlinkTarget));
        }
        entry.insert(QStringLiteral("original_exists"), existed);
        const QFileInfo permissionInfo = isSymlink ? targetInfo : info;
        entry.insert(QStringLiteral("original_permissions"), existed ? unixPermissions(permissionInfo.permissions()) : 0);
        entry.insert(QStringLiteral("original_owner_id"), existed ? static_cast<int>(permissionInfo.ownerId()) : -1);
        entry.insert(QStringLiteral("original_group_id"), existed ? static_cast<int>(permissionInfo.groupId()) : -1);

        if (existed) {
            QFile file(path);
            if (!file.open(QIODevice::ReadOnly)) {
                qWarning() << "Could not back up configuration file:" << path << file.errorString();
                return false;
            }
            const QByteArray contents = file.readAll();
            entry.insert(QStringLiteral("original_data"), QString::fromLatin1(contents.toBase64()));
            entry.insert(QStringLiteral("original_sha256"), QString::fromLatin1(sha256(contents)));
        } else {
            entry.insert(QStringLiteral("original_data"), QString());
            entry.insert(QStringLiteral("original_sha256"), QString());
        }

        entry.insert(QStringLiteral("expected_exists"), existed);
        entry.insert(QStringLiteral("expected_sha256"), entry.value(QStringLiteral("original_sha256")));
        entries.append(entry);
    }

    QJsonObject root;
    root.insert(QStringLiteral("version"), 1);
    root.insert(QStringLiteral("files"), entries);
    return writeManifest(manifestPath, root);
}

// Called after AeroThemePlasma finishes applying its settings. During removal,
// a file is restored only while it still matches this exact recorded state.
inline bool captureExpectedState(const QString &manifestPath)
{
    QJsonObject root;
    if (!readManifest(manifestPath, &root)) {
        return false;
    }

    QJsonArray entries = root.value(QStringLiteral("files")).toArray();
    for (qsizetype i = 0; i < entries.size(); ++i) {
        QJsonObject entry = entries.at(i).toObject();
        if (entry.value(QStringLiteral("skipped")).toBool()) {
            continue;
        }

        const QString path = entry.value(QStringLiteral("path")).toString();
        const QFileInfo info(path);
        const bool expectedSymlink = entry.value(QStringLiteral("is_symlink")).toBool();
        const bool sameSymlinkTarget = !expectedSymlink
            || QDir::cleanPath(info.canonicalFilePath()) == entry.value(QStringLiteral("symlink_target")).toString();

        if (info.isSymLink() != expectedSymlink || !sameSymlinkTarget
            || (!info.isSymLink() && info.exists() && !info.isFile())) {
            entry.insert(QStringLiteral("expected_unsafe"), true);
            entry.insert(QStringLiteral("reason"), QStringLiteral("path type or symlink target changed"));
        } else if (info.exists()) {
            QFile file(path);
            if (!file.open(QIODevice::ReadOnly)) {
                qWarning() << "Could not capture applied configuration state:" << path;
                return false;
            }
            entry.insert(QStringLiteral("expected_exists"), true);
            entry.insert(QStringLiteral("expected_sha256"), QString::fromLatin1(sha256(file.readAll())));
        } else {
            entry.insert(QStringLiteral("expected_exists"), false);
            entry.insert(QStringLiteral("expected_sha256"), QString());
        }

        entries.replace(i, entry);
    }

    root.insert(QStringLiteral("files"), entries);
    return writeManifest(manifestPath, root);
}
} // namespace AtpRollback
