/* The common prelude's blob accessors. mxq_blob_bytes hands out the only
 * pointer into core memory this interface exposes. */

#include "mxq_internal.hpp"

extern "C" {

const uint8_t *MXQ_CALL mxq_blob_bytes(const MxqBlob *blob) {
    return blob != nullptr ? blob->data : nullptr;
}

size_t MXQ_CALL mxq_blob_len(const MxqBlob *blob) {
    return blob != nullptr ? blob->len : 0;
}

void MXQ_CALL mxq_blob_release(MxqBlob *blob) {
    if (blob == nullptr) {
        return;
    }
    delete[] blob->data; /* paired with the new[] in the producing codec */
    blob->data = nullptr;
    blob->len = 0;
    delete blob;
}

} /* extern "C" */
