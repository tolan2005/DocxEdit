//
//  FileWatcher.swift
//  DocxEdit
//
//  Слежение за файлом документа на диске: запись, атомарная замена (новый файл
//  поверх старого — так сохраняет большинство программ), удаление. После замены
//  или удаления подписка заново открывается по тому же пути. Колбэк — на main,
//  через 0.3 с после последнего события (серия записей = одна перезагрузка).
//

import Foundation

final class FileWatcher {
    let url: URL
    private let onChange: () -> Void
    private var source: DispatchSourceFileSystemObject?
    private var pending: DispatchWorkItem?

    init(url: URL, onChange: @escaping () -> Void) {
        self.url = url
        self.onChange = onChange
        start(attempt: 0)
    }

    deinit {
        pending?.cancel()
        source?.cancel()
    }

    private func start(attempt: Int) {
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else {
            // Файла пока нет (идёт замена) — несколько повторов, потом сдаёмся.
            if attempt < 10 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.start(attempt: attempt + 1) }
            }
            return
        }
        let s = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd,
                                                          eventMask: [.write, .extend, .delete, .rename],
                                                          queue: .main)
        s.setEventHandler { [weak self, weak s] in
            guard let self, let s else { return }
            if !s.data.isDisjoint(with: [.delete, .rename]) {
                s.cancel()
                self.source = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in self?.start(attempt: 0) }
            }
            self.schedule()
        }
        s.setCancelHandler { close(fd) }
        source = s
        s.resume()
    }

    private func schedule() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.onChange() }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }
}
