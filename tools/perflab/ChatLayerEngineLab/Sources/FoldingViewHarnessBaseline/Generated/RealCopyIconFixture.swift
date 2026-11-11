import Cocoa

func makeRealCopyIconFixture() -> NSImage {
    let image = NSImage(size: NSSize(width: 16, height: 16))
    if let data = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAACXBIWXMAAAsTAAALEwEAmpwYAAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAADaSURBVHgBrZONDYIwEIVP4wBsIG7ABsoEsIG4AU6gG+gG6AZuoBsYJ4ANZAN9F19jrQX84SVfgOu7l14bRP7UoGVtRlQV2PlMw4bmFBR8D/i+ki8UEVUIruDcFaLGIygdc8ha0BWizTkbtuBGc8CAwqrnpsk+RDXF8jiwNRun4AD2IKNP6wmY6MdI/KppjLkzYagZKfE1lVw0ptJCt506a9K2g4pbNIE6c8RxXtQUYAepaj7N/NWnAa70FsZg8WtA5hbsAL2qDbh4Gudg6am//UyZPA/O1on0rzudEC0FYRKlUAAAAABJRU5ErkJggg=="), let representation = NSBitmapImageRep(data: data) {
        representation.size = image.size
        image.addRepresentation(representation)
    }
    if let data = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAYAAABzenr0AAAACXBIWXMAABYlAAAWJQFJUiTwAAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAFySURBVHgB7VbRbYMwEH2q+t+MwAgdgU5QRnAnCBuUbpANcDdoJ0CdoNmAbEA7AfEpZ8WybGMbiBIpT3pyYvu4x/HOANxxgygVO8VBcTTYKwqsjMpK6uI7VsQvJ2kUN8a8uJQIKn3vmBecmAQOuEAlfAJaxecUEY+BNXrer9bcn+KP4lcgbq/4glO1Gp77QCLoTlKMps1pCkuqhAnBQRRc83+BsNEKI6acK2LHAbVjbTQS2RfdYbpFS0RA8mYBvwDfnTU4t6qLLRYSAKSVV/gEPCAf2u3UGQ0y+z5VwIHHcikRqQI+eeyYVNItCwGLqDETEn4PEKbc3jtiBDweCJ2EPtQsomCaaB1zQeQIIBxw9oMtIAlzuiAF+tX9by/kViA2acWj7o59TKBE2IQhmAeVbVbpClizAlLxiX9/w/MKX1MAlfttatOSJtwgAy4B2ih0whWIT7614rNBF6PTbMxkhQVQ4GSiITIp7esQ+cFxx1XhCGfDrreSuk/IAAAAAElFTkSuQmCC"), let representation = NSBitmapImageRep(data: data) {
        representation.size = image.size
        image.addRepresentation(representation)
    }
    return image
}
