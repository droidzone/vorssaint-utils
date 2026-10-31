// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct ShelfImageFitStrings {
    let menu: String
    let menuCount: String
    let title: String
    let caption: String
    let target: String
    let kilobytes: String
    let nowFormat: String
    let imagesFormat: String
    let compress: String
    let cancel: String
    let done: String
    let workingFormat: String
    let fittedOne: String
    let fittedMany: String
    let alreadyOne: String
    let alreadyMany: String
    let failedOne: String
    let failedMany: String
    let help: String

    static func localized(_ language: AppLanguage) -> ShelfImageFitStrings {
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
        case .zhHans: return .zhHans
        case .zhTW: return .zhTW
        case .zhHK: return .zhHK
        case .uk: return .uk
        }
    }
}

extension ShelfImageFitStrings {
    static let enUS = ShelfImageFitStrings(
        menu: "Compress to size…",
        menuCount: "Compress %d images to size…",
        title: "Compress to size",
        caption: "Each picture stays under this size. It is scaled down without stretching and saved as JPEG, using the steps in Settings. An animation keeps its first frame.",
        target: "Target size",
        kilobytes: "KB",
        nowFormat: "Now %@",
        imagesFormat: "%d images · %@",
        compress: "Compress",
        cancel: "Cancel",
        done: "Done",
        workingFormat: "Compressing %d of %d…",
        fittedOne: "Compressed",
        fittedMany: "%d compressed",
        alreadyOne: "Already under this size",
        alreadyMany: "%d already under this size",
        failedOne: "Could not get it under this size",
        failedMany: "%d could not fit",
        help: "Compress images to a size"
    )

    static let ptBR = ShelfImageFitStrings(
        menu: "Comprimir até um tamanho…",
        menuCount: "Comprimir %d imagens até um tamanho…",
        title: "Comprimir até um tamanho",
        caption: "Cada imagem fica abaixo deste tamanho. Ela é reduzida sem distorcer e salva como JPEG, nos passos definidos em Ajustes. Uma animação guarda o primeiro quadro.",
        target: "Tamanho desejado",
        kilobytes: "KB",
        nowFormat: "Agora %@",
        imagesFormat: "%d imagens · %@",
        compress: "Comprimir",
        cancel: "Cancelar",
        done: "Concluído",
        workingFormat: "Comprimindo %d de %d…",
        fittedOne: "Comprimida",
        fittedMany: "%d comprimidas",
        alreadyOne: "Já está abaixo deste tamanho",
        alreadyMany: "%d já estão abaixo deste tamanho",
        failedOne: "Não foi possível ficar abaixo deste tamanho",
        failedMany: "%d não couberam",
        help: "Comprimir imagens até um tamanho"
    )

    static let es = ShelfImageFitStrings(
        menu: "Comprimir a un tamaño…",
        menuCount: "Comprimir %d imágenes a un tamaño…",
        title: "Comprimir a un tamaño",
        caption: "Cada imagen queda por debajo de este tamaño. Se reduce sin deformarse y se guarda como JPEG, siguiendo los pasos de Ajustes. Una animación conserva el primer fotograma.",
        target: "Tamaño objetivo",
        kilobytes: "KB",
        nowFormat: "Ahora %@",
        imagesFormat: "%d imágenes · %@",
        compress: "Comprimir",
        cancel: "Cancelar",
        done: "Listo",
        workingFormat: "Comprimiendo %d de %d…",
        fittedOne: "Comprimida",
        fittedMany: "%d comprimidas",
        alreadyOne: "Ya está por debajo de este tamaño",
        alreadyMany: "%d ya están por debajo de este tamaño",
        failedOne: "No se pudo dejar por debajo de este tamaño",
        failedMany: "%d no cupieron",
        help: "Comprimir imágenes a un tamaño"
    )

    static let de = ShelfImageFitStrings(
        menu: "Auf Größe komprimieren…",
        menuCount: "%d Bilder auf Größe komprimieren…",
        title: "Auf Größe komprimieren",
        caption: "Jedes Bild bleibt unter dieser Größe. Es wird ohne Verzerrung verkleinert und als JPEG gespeichert, nach den Schritten in den Einstellungen. Eine Animation behält das erste Bild.",
        target: "Zielgröße",
        kilobytes: "KB",
        nowFormat: "Jetzt %@",
        imagesFormat: "%d Bilder · %@",
        compress: "Komprimieren",
        cancel: "Abbrechen",
        done: "Fertig",
        workingFormat: "Komprimiere %d von %d…",
        fittedOne: "Komprimiert",
        fittedMany: "%d komprimiert",
        alreadyOne: "Liegt schon unter dieser Größe",
        alreadyMany: "%d liegen schon unter dieser Größe",
        failedOne: "Konnte diese Größe nicht unterschreiten",
        failedMany: "%d passten nicht",
        help: "Bilder auf eine Größe komprimieren"
    )

    static let fr = ShelfImageFitStrings(
        menu: "Compresser à une taille…",
        menuCount: "Compresser %d images à une taille…",
        title: "Compresser à une taille",
        caption: "Chaque image reste sous cette taille. Elle est réduite sans être étirée, puis enregistrée en JPEG selon les étapes des réglages. Une animation garde sa première image.",
        target: "Taille visée",
        kilobytes: "Ko",
        nowFormat: "Actuellement %@",
        imagesFormat: "%d images · %@",
        compress: "Compresser",
        cancel: "Annuler",
        done: "Terminé",
        workingFormat: "Compression %d sur %d…",
        fittedOne: "Compressée",
        fittedMany: "%d compressées",
        alreadyOne: "Déjà sous cette taille",
        alreadyMany: "%d déjà sous cette taille",
        failedOne: "Impossible de passer sous cette taille",
        failedMany: "%d n’ont pas tenu",
        help: "Compresser les images à une taille"
    )

    static let it = ShelfImageFitStrings(
        menu: "Comprimi a una dimensione…",
        menuCount: "Comprimi %d immagini a una dimensione…",
        title: "Comprimi a una dimensione",
        caption: "Ogni immagine resta sotto questa dimensione. Viene rimpicciolita senza deformarla e salvata come JPEG, secondo i passi nelle impostazioni. Un’animazione tiene il primo fotogramma.",
        target: "Dimensione desiderata",
        kilobytes: "KB",
        nowFormat: "Ora %@",
        imagesFormat: "%d immagini · %@",
        compress: "Comprimi",
        cancel: "Annulla",
        done: "Fatto",
        workingFormat: "Compressione %d di %d…",
        fittedOne: "Compressa",
        fittedMany: "%d compresse",
        alreadyOne: "È già sotto questa dimensione",
        alreadyMany: "%d sono già sotto questa dimensione",
        failedOne: "Impossibile restare sotto questa dimensione",
        failedMany: "%d non ci stanno",
        help: "Comprimi le immagini a una dimensione"
    )

    static let tr = ShelfImageFitStrings(
        menu: "Boyuta sıkıştır…",
        menuCount: "%d görseli boyuta sıkıştır…",
        title: "Boyuta sıkıştır",
        caption: "Her görsel bu boyutun altında kalır. Oran korunarak küçültülür ve Ayarlar’daki adımlarla JPEG olarak kaydedilir. Bir animasyon ilk karesini tutar.",
        target: "Hedef boyut",
        kilobytes: "KB",
        nowFormat: "Şu an %@",
        imagesFormat: "%d görsel · %@",
        compress: "Sıkıştır",
        cancel: "Vazgeç",
        done: "Bitti",
        workingFormat: "%d / %d sıkıştırılıyor…",
        fittedOne: "Sıkıştırıldı",
        fittedMany: "%d sıkıştırıldı",
        alreadyOne: "Zaten bu boyutun altında",
        alreadyMany: "%d zaten bu boyutun altında",
        failedOne: "Bu boyutun altına inilemedi",
        failedMany: "%d sığmadı",
        help: "Görselleri bir boyuta sıkıştır"
    )

    static let ru = ShelfImageFitStrings(
        menu: "Сжать до размера…",
        menuCount: "Сжать %d изображений до размера…",
        title: "Сжать до размера",
        caption: "Каждая картинка остаётся меньше этого размера. Она уменьшается без искажения пропорций и сохраняется как JPEG по шагам из настроек. Анимация сохраняет первый кадр.",
        target: "Нужный размер",
        kilobytes: "КБ",
        nowFormat: "Сейчас %@",
        imagesFormat: "%d изображений · %@",
        compress: "Сжать",
        cancel: "Отменить",
        done: "Готово",
        workingFormat: "Сжатие %d из %d…",
        fittedOne: "Сжато",
        fittedMany: "%d сжато",
        alreadyOne: "Уже меньше этого размера",
        alreadyMany: "%d уже меньше этого размера",
        failedOne: "Не удалось уложиться в этот размер",
        failedMany: "%d не уместились",
        help: "Сжать изображения до размера"
    )

    static let uk = ShelfImageFitStrings(
        menu: "Стиснути до розміру…",
        menuCount: "Стиснути %d зображень до розміру…",
        title: "Стиснути до розміру",
        caption: "Кожне зображення лишається меншим за цей розмір. Воно зменшується без спотворення і зберігається як JPEG за кроками з параметрів. Анімація зберігає перший кадр.",
        target: "Потрібний розмір",
        kilobytes: "КБ",
        nowFormat: "Зараз %@",
        imagesFormat: "%d зображень · %@",
        compress: "Стиснути",
        cancel: "Скасувати",
        done: "Готово",
        workingFormat: "Стискання %d з %d…",
        fittedOne: "Стиснуто",
        fittedMany: "%d стиснуто",
        alreadyOne: "Уже менше за цей розмір",
        alreadyMany: "%d уже менше за цей розмір",
        failedOne: "Не вдалося вкластися в цей розмір",
        failedMany: "%d не вмістилися",
        help: "Стиснути зображення до розміру"
    )

    static let sk = ShelfImageFitStrings(
        menu: "Komprimovať na veľkosť…",
        menuCount: "Komprimovať %d obrázkov na veľkosť…",
        title: "Komprimovať na veľkosť",
        caption: "Každý obrázok zostane pod touto veľkosťou. Zmenší sa bez roztiahnutia a uloží ako JPEG podľa krokov v nastaveniach. Animácia si nechá prvé políčko.",
        target: "Cieľová veľkosť",
        kilobytes: "KB",
        nowFormat: "Teraz %@",
        imagesFormat: "%d obrázkov · %@",
        compress: "Komprimovať",
        cancel: "Zrušiť",
        done: "Hotovo",
        workingFormat: "Komprimuje sa %d z %d…",
        fittedOne: "Komprimované",
        fittedMany: "%d komprimovaných",
        alreadyOne: "Už je pod touto veľkosťou",
        alreadyMany: "%d už je pod touto veľkosťou",
        failedOne: "Nepodarilo sa dostať pod túto veľkosť",
        failedMany: "%d sa nezmestilo",
        help: "Komprimovať obrázky na veľkosť"
    )

    static let ja = ShelfImageFitStrings(
        menu: "サイズを指定して圧縮…",
        menuCount: "%d枚の画像をサイズを指定して圧縮…",
        title: "サイズを指定して圧縮",
        caption: "それぞれの画像がこのサイズ未満になります。縦横比を保って縮小し、設定の手順に沿って JPEG として保存します。アニメーションは最初のフレームだけ残します。",
        target: "目標サイズ",
        kilobytes: "KB",
        nowFormat: "現在 %@",
        imagesFormat: "%d枚 · %@",
        compress: "圧縮",
        cancel: "キャンセル",
        done: "完了",
        workingFormat: "%2$d枚中%1$d枚を圧縮しています…",
        fittedOne: "圧縮しました",
        fittedMany: "%d枚を圧縮しました",
        alreadyOne: "すでにこのサイズ未満です",
        alreadyMany: "%d枚はすでにこのサイズ未満です",
        failedOne: "このサイズ未満にできませんでした",
        failedMany: "%d枚は収まりませんでした",
        help: "画像を指定サイズまで圧縮"
    )

    static let ko = ShelfImageFitStrings(
        menu: "크기에 맞춰 압축…",
        menuCount: "이미지 %d개를 크기에 맞춰 압축…",
        title: "크기에 맞춰 압축",
        caption: "각 그림이 이 크기보다 작게 유지됩니다. 비율을 유지한 채 줄이고, 설정의 단계에 따라 JPEG로 저장합니다. 애니메이션은 첫 프레임만 남깁니다.",
        target: "목표 크기",
        kilobytes: "KB",
        nowFormat: "현재 %@",
        imagesFormat: "이미지 %d개 · %@",
        compress: "압축",
        cancel: "취소",
        done: "완료",
        workingFormat: "%2$d개 중 %1$d개 압축 중…",
        fittedOne: "압축했습니다",
        fittedMany: "%d개를 압축했습니다",
        alreadyOne: "이미 이 크기보다 작습니다",
        alreadyMany: "%d개는 이미 이 크기보다 작습니다",
        failedOne: "이 크기 아래로 줄이지 못했습니다",
        failedMany: "%d개는 맞추지 못했습니다",
        help: "이미지를 지정한 크기로 압축"
    )

    static let zhHans = ShelfImageFitStrings(
        menu: "压缩到指定大小…",
        menuCount: "将 %d 张图片压缩到指定大小…",
        title: "压缩到指定大小",
        caption: "每张图片都会小于这个大小。按原比例缩小，并按设置中的步骤存为 JPEG。动画只保留第一帧。",
        target: "目标大小",
        kilobytes: "KB",
        nowFormat: "目前 %@",
        imagesFormat: "%d 张图片 · %@",
        compress: "压缩",
        cancel: "取消",
        done: "完成",
        workingFormat: "正在压缩 %1$d / %2$d…",
        fittedOne: "已压缩",
        fittedMany: "已压缩 %d 张",
        alreadyOne: "已经小于这个大小",
        alreadyMany: "%d 张已经小于这个大小",
        failedOne: "无法压到这个大小以下",
        failedMany: "%d 张未能压到目标以下",
        help: "把图片压缩到指定大小"
    )

    static let zhTW = ShelfImageFitStrings(
        menu: "壓縮到指定大小…",
        menuCount: "將 %d 張圖片壓縮到指定大小…",
        title: "壓縮到指定大小",
        caption: "每張圖片都會小於這個大小。依原比例縮小，並按設定中的步驟存成 JPEG。動畫只保留第一幀。",
        target: "目標大小",
        kilobytes: "KB",
        nowFormat: "目前 %@",
        imagesFormat: "%d 張圖片 · %@",
        compress: "壓縮",
        cancel: "取消",
        done: "完成",
        workingFormat: "正在壓縮 %1$d / %2$d…",
        fittedOne: "已壓縮",
        fittedMany: "已壓縮 %d 張",
        alreadyOne: "已經小於這個大小",
        alreadyMany: "%d 張已經小於這個大小",
        failedOne: "無法壓到這個大小以下",
        failedMany: "%d 張未能壓到目標以下",
        help: "把圖片壓縮到指定大小"
    )

    static let zhHK = ShelfImageFitStrings(
        menu: "壓縮到指定大小…",
        menuCount: "將 %d 張圖片壓縮到指定大小…",
        title: "壓縮到指定大小",
        caption: "每張圖片都會細過呢個大小。按原比例縮小，並跟設定入面嘅步驟存成 JPEG。動畫只保留第一幀。",
        target: "目標大小",
        kilobytes: "KB",
        nowFormat: "而家 %@",
        imagesFormat: "%d 張圖片 · %@",
        compress: "壓縮",
        cancel: "取消",
        done: "完成",
        workingFormat: "壓縮緊 %1$d / %2$d…",
        fittedOne: "已壓縮",
        fittedMany: "已壓縮 %d 張",
        alreadyOne: "已經細過呢個大小",
        alreadyMany: "%d 張已經細過呢個大小",
        failedOne: "無法壓到呢個大小以下",
        failedMany: "%d 張未能壓到目標以下",
        help: "將圖片壓縮到指定大小"
    )
}
