// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct ShelfFileNameStrings {
    let help: String
    let addVor: String
    let overwrite: String

    static func localized(_ language: AppLanguage) -> ShelfFileNameStrings {
        switch language {
        case .enUS: return .enUS
        case .ptBR: return .ptBR
        case .tr: return .tr
        case .ru: return .ru
        case .es: return .es
        case .sk: return .sk
        case .de: return .de
        case .fr: return .fr
        case .it: return .it
        case .ja: return .ja
        case .ko: return .ko
        case .uk: return .uk
        case .zhHans: return .zhHans
        case .zhTW: return .zhTW
        case .zhHK: return .zhHK
        }
    }
}

extension ShelfFileNameStrings {
    static let enUS = ShelfFileNameStrings(
        help: "How a file is named when the name would stay the same",
        addVor: "Add _vor before the extension",
        overwrite: "Overwrite the original name, keep _bak"
    )
    static let ptBR = ShelfFileNameStrings(
        help: "Como o arquivo é nomeado quando o nome seria o mesmo",
        addVor: "Adicionar _vor antes da extensão",
        overwrite: "Substituir o nome original e guardar _bak"
    )
    static let es = ShelfFileNameStrings(
        help: "Cómo se nombra el archivo cuando el nombre seguiría igual",
        addVor: "Añadir _vor antes de la extensión",
        overwrite: "Sobrescribir el nombre original y conservar _bak"
    )
    static let de = ShelfFileNameStrings(
        help: "Wie eine Datei heißt, wenn der Name gleich bliebe",
        addVor: "_vor vor der Endung anfügen",
        overwrite: "Originalnamen überschreiben, _bak behalten"
    )
    static let fr = ShelfFileNameStrings(
        help: "Comment le fichier est nommé lorsque le nom resterait le même",
        addVor: "Ajouter _vor avant l’extension",
        overwrite: "Écraser le nom d’origine et garder _bak"
    )
    static let it = ShelfFileNameStrings(
        help: "Come viene nominato il file quando il nome resterebbe uguale",
        addVor: "Aggiungi _vor prima dell’estensione",
        overwrite: "Sostituisci il nome originale e tieni _bak"
    )
    static let tr = ShelfFileNameStrings(
        help: "Ad aynı kalacakken dosyanın nasıl adlandırılacağı",
        addVor: "Uzantıdan önce _vor ekle",
        overwrite: "Özgün adın üzerine yaz, _bak olarak sakla"
    )
    static let ru = ShelfFileNameStrings(
        help: "Как назвать файл, если имя осталось бы прежним",
        addVor: "Добавить _vor перед расширением",
        overwrite: "Заменить исходное имя, оригинал сохранить как _bak"
    )
    static let uk = ShelfFileNameStrings(
        help: "Як назвати файл, якщо ім’я лишилося б тим самим",
        addVor: "Додати _vor перед розширенням",
        overwrite: "Замінити початкове ім’я, оригінал зберегти як _bak"
    )
    static let sk = ShelfFileNameStrings(
        help: "Ako sa súbor pomenuje, keď by názov ostal rovnaký",
        addVor: "Pridať _vor pred príponu",
        overwrite: "Prepísať pôvodný názov a ponechať _bak"
    )
    static let ja = ShelfFileNameStrings(
        help: "名前が同じになるときの付け方",
        addVor: "拡張子の前に _vor を付ける",
        overwrite: "元の名前で上書きし、元のファイルは _bak で残す"
    )
    static let ko = ShelfFileNameStrings(
        help: "이름이 같아질 때 파일을 무엇이라 부를지",
        addVor: "확장자 앞에 _vor 붙이기",
        overwrite: "원래 이름으로 덮어쓰고 원본은 _bak 으로 남기기"
    )
    static let zhHans = ShelfFileNameStrings(
        help: "文件名将保持不变时如何命名",
        addVor: "在扩展名之前加上 _vor",
        overwrite: "沿用原文件名，并把原文件留为 _bak"
    )
    static let zhTW = ShelfFileNameStrings(
        help: "檔名將維持不變時如何命名",
        addVor: "在副檔名之前加上 _vor",
        overwrite: "沿用原檔名，並把原檔留為 _bak"
    )
    static let zhHK = ShelfFileNameStrings(
        help: "檔名會維持不變時點樣命名",
        addVor: "喺副檔名前面加上 _vor",
        overwrite: "沿用原檔名，並把原檔留為 _bak"
    )
}
