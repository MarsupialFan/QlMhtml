//
//  PreviewProvider.swift
//  QlMhtml
//
//  Created by Adi Ofer on 12/2/23.
//

import Cocoa
import MimeParser
import Quartz
import os

//
// https://www.hackingwithswift.com/example-code/strings/how-to-remove-a-prefix-from-a-string
//
extension String {
    func deletePrefix(_ prefix: String) -> String {
        guard self.hasPrefix(prefix) else {
            return self
        }
        return String(self.dropFirst(prefix.count))
    }
}

let logger = Logger(subsystem: "QlMhtml", category: "MimeParser")

class MhtmlPreviewProvider: QLPreviewProvider, QLPreviewingController {


    /*
     Use a QLPreviewProvider to provide data-based previews.

     To set up your extension as a data-based preview extension:

     - Modify the extension's Info.plist by setting
       <key>QLIsDataBasedPreview</key>
       <true/>

     - Add the supported content types to QLSupportedContentTypes array in the extension's Info.plist.

     - Change the NSExtensionPrincipalClass to this class.
       e.g.
       <key>NSExtensionPrincipalClass</key>
       <string>$(PRODUCT_MODULE_NAME).PreviewProvider</string>

     - Implement providePreview(for:)
     */

    func providePreview(for request: QLFilePreviewRequest) async throws -> QLPreviewReply {
        let contentType = UTType.html
        let reply = QLPreviewReply.init(dataOfContentType: contentType, contentSize: CGSize.init(width: 800, height: 800)) { (htmlReply : QLPreviewReply) in
            htmlReply.stringEncoding = .utf8

            guard let mimeParser = MimeParser(for: request.fileURL) else {
                return Data(self.htmlWrap(errorMessage: "\(#function): Failed to instantiate MimeParser").utf8)
            }

            do {
                let mimeArchive = try mimeParser.parse()

                var mainBody: Data? = nil
                if (mimeArchive.subResources.isEmpty) {
                    // The case of a single part Mime
                    mainBody = mimeArchive.mainResource.body
                } else {
                    // The case of a multipart Mime archive
                    for (i, subResource) in mimeArchive.subResources.enumerated() {
                        if i == 0 {
                            mainBody = subResource.body
                            continue
                        }

                        // Add (to the reply) all the subresources as attachments
                        guard let url = subResource.header.contentLocation?.deletePrefix("cid:") else {
                            logger.error("\(#function): Missing content location at resource #\(i), skipping...")
                            continue
                        }
                        let body = subResource.body

                        // Determine the contentType's UTType value
                        var contentTypeUTType: UTType
                        switch subResource.header.contentSubtype {
                        case "css":
                            guard let cssUTType = UTType("public.css") else {
                                logger.error("\(#function): Failed to find UTType of a CSS resource, skipping...")
                                continue
                            }
                            contentTypeUTType = cssUTType
                        case "gif":
                            contentTypeUTType = .gif
                        case "jpeg":
                            contentTypeUTType = .jpeg
                        case "png":
                            contentTypeUTType = .png
                        case "webp":
                            contentTypeUTType = .webP
                        default:
                            logger.error("\(#function): Unsupported content subtype \(subResource.header.contentSubtype), skipping...")
                            continue
                        }
                        htmlReply.attachments[url] = QLPreviewReplyAttachment(data: body, contentType: contentTypeUTType)
                    }
                }

                guard let body = mainBody else {
                    logger.error("\(#function): Main body not found")
                    return Data(self.htmlWrap(errorMessage: "\(#function): Main body not found").utf8)
                }
                return body
            } catch {
                // htmlReply.title = "QlMhtml error message"
                return Data(self.htmlWrap(errorMessage: "Caught exception, error: \(error.localizedDescription)").utf8)
            }
        }

        return reply
    }

    private func htmlWrap(errorMessage: String) -> String {
        return """
            <!DOCTYPE html>
            <html>
            <body>
            <h1>QlMhtml Error</h1>
            \(errorMessage)
            </body>
            </html>

            """
    }
}
