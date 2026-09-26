# Dành cho chatbot web: ghép cấu hình Kilo, KHÔNG truy cập máy người dùng

Người dùng sẽ **dán nội dung cấu hình hiện tại** (`kilo.json` hoặc `kilo.jsonc`) và guide này vào chat. Bạn không có quyền đọc file, chạy `kilo debug`, xem credential hoặc cài đặt. Chỉ làm việc với văn bản được cung cấp; nếu thiếu cấu hình, yêu cầu người dùng dán bản đã che bí mật. Không nói rằng bạn đã kiểm tra trạng thái Kilo thực tế.

## Đầu vào và an toàn

- Trước khi gửi cho chatbot, người dùng nên thay mọi API key/token/password/URL có secret bằng placeholder riêng, ví dụ `REDACTED_API_KEY_1`. Giữ nguyên **tên field, cấu trúc, comment và các field không bí mật**. Đừng gửi secret thật lên web. Khi chép lại, giữ placeholder **nguyên văn**; người dùng thay giá trị gốc **cục bộ** sau đó. Nếu đầu vào chứa secret thật: không nhắc lại giá trị; trả **patch/vị trí chỉnh sửa**, không xuất lại toàn bộ config. Không thể tái tạo bí mật từ placeholder: nhắc người dùng giữ bản gốc để khôi phục.
- Giữ đúng định dạng đầu vào: JSONC giữ comment/trailing comma hợp lệ; JSON giữ JSON hợp lệ. Không tự đổi toàn bộ file sang JSON, không xoá field chưa hiểu. Nếu config chưa được cung cấp, hoặc sai cú pháp và không thể xác định chỗ ghép an toàn, hỏi lại thay vì bịa provider/model.

## Chỉ chỉnh những gì cần thiết

1. Ở cấp gốc: `"default_agent": "prime"`, `"subagent_depth": 1`. Thay giá trị nếu đã tồn tại; nếu chưa có thì thêm field. `subagent_depth` có mặt trong cấu hình hiệu lực của Kilo CLI 7.8.1 đã thử nhưng **chưa chứng minh được cơ chế giới hạn nesting trong upstream**; không quảng cáo đây là hàng rào bảo mật.
2. Nếu **đã có** `provider.9router` và muốn dùng timeout streaming: merge `"chunkTimeout": 1800000` vào `provider.9router.options` hiện tại. Nếu đã đúng giá trị, không thay. Đây là tối đa 30 phút **giữa các chunk im lặng nếu SDK hỗ trợ**, không phải timeout toàn Sub; không giới hạn tool/chuỗi request. Giữ `options.timeout` hiện hữu; không đổi thành `false`. Nếu **không có** `provider.9router`/model `sub`, **không tạo provider rỗng/credential giả**: hỏi người dùng thông tin thiết lập provider hoặc nêu bước còn thiếu.
3. KHÔNG thêm `agent.prime`, `agent.sub`, model của Prime, permissions/mode/prompt vào config: `prime.md` và `sub.md` sở hữu các mục này; `sub.md` cố định `9router/sub`. Không thêm `maxSteps`/`steps` làm chống treo. Không sửa built-ins, MCP, plugins, auth, provider khác, model metadata hay field không liên quan. Installer cũng không được sửa `kilo.json/jsonc`.

## Đầu ra cho người dùng

- Nếu bản dán **đã che toàn bộ secrets**: trả **toàn bộ config có thể copy**, giữ thứ tự, comments, placeholders và mọi field không liên quan; chỉ thay ba vị trí cần thiết ở trên. Với JSONC, kiểm tra dấu phẩy và comment. Nếu không cần chỉnh, nói "không cần sửa" và không in lại file.
- Nếu bản dán **còn secrets thật** hoặc quá dài để bảo toàn chính xác: trả patch định vị rõ từng field (old → new), **không lặp lại secret**, không xuất toàn bộ file. Nói rõ điều gì chưa thể xác minh. Không âm thầm đoán `9router` model key.
- Chốt bằng danh sách thay đổi ngắn + một bước kiểm tra **để người dùng tự chạy cục bộ sau khi lưu**: `kilo debug config` (chỉ kiểm tra field không bí mật; không dán toàn bộ output lên web), `kilo debug agent prime`, `kilo debug agent sub` (phải thấy primary/subagent và `9router/sub`). Trước khi áp dụng, người dùng tự sao lưu file gốc. Chỉ chạy `kilo run --auto --agent prime` trên repo đáng tin cậy.
