//
//  DocumentError.swift
//  DocxCore
//
//  Ошибки модели документа и сериализации.
//

import Foundation

public enum DocumentError: Error, LocalizedError, Equatable {
    case invalidDocument(String)
    case unsupportedFormat(String)
    case encodingError(String)
    case ioError(String)
    case xmlParseError(String)
    case missingRequiredField(String)
    case outOfRange(String)
    case notImplemented(String)

    public var errorDescription: String? {
        switch self {
        case .invalidDocument(let s): return "Недопустимый документ: \(s)"
        case .unsupportedFormat(let s): return "Неподдерживаемый формат: \(s)"
        case .encodingError(let s): return "Ошибка кодировки: \(s)"
        case .ioError(let s): return "Ошибка ввода-вывода: \(s)"
        case .xmlParseError(let s): return "Ошибка разбора XML: \(s)"
        case .missingRequiredField(let s): return "Отсутствует обязательное поле: \(s)"
        case .outOfRange(let s): return "Значение вне диапазона: \(s)"
        case .notImplemented(let s): return "Не реализовано: \(s)"
        }
    }
}
