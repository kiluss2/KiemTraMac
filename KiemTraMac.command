#!/bin/bash
# =====================================================================
#  KIỂM TRA MAC CŨ TRƯỚC KHI MUA - dùng cho mọi máy Mac (Apple silicon & Intel, macOS 13+)
#  Nhấp đúp để chạy. Chỉ ĐỌC thông tin, không cài và không sửa gì trên máy.
#  Đọc: cấu hình, Activation Lock, MDM / máy công ty, SIP, pin, SSD (S.M.A.R.T.),
#        lịch sử kernel panic, còn được cập nhật macOS không.
# =====================================================================

export LC_ALL=en_US.UTF-8
DIR="$(cd "$(dirname "$0")" && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
# Tải bằng ZIP qua trình duyệt thì smartctl bị gắn cờ quarantine → gỡ để chạy được
xattr -dr com.apple.quarantine "$DIR" 2>/dev/null

FAILS=(); PENDS=(); WARNS=(); OKS=(); INFO=(); USAGE_LINES=()
fail() { FAILS+=("$1"); }
pend() { PENDS+=("$1"); }
warn() { WARNS+=("$1"); }
ok()   { OKS+=("$1"); }
num()  { [[ "$1" =~ ^-?[0-9]+$ ]]; }
calc() { awk "BEGIN { printf \"%.${2:-1}f\", $1 }"; }
gt()   { awk "BEGIN { exit !($1 > $2) }"; }

region_name() {
  case "$1" in
    J/A) echo "Nhật (bàn phím JIS)" ;; LL/A) echo "Mỹ" ;; VN/A) echo "Việt Nam" ;;
    ZA/A) echo "Singapore/Malaysia" ;; ZP/A) echo "Hồng Kông" ;; CH/A) echo "Trung Quốc" ;;
    KH/A) echo "Hàn Quốc" ;; TA/A) echo "Đài Loan" ;; TH/A) echo "Thái Lan" ;;
    X/A) echo "Úc" ;; C/A) echo "Canada" ;; B/A) echo "Anh" ;; D/A) echo "Đức" ;;
    F/A) echo "Pháp" ;; "") echo "không rõ" ;; *) echo "mã $1" ;;
  esac
}

# ------------------------------------------------------------------
#  Hỏi 2 câu tuỳ chọn (Enter để bỏ qua)
#  Ngày mua không có trong máy (chỉ Apple giữ), nên phải nhập tay từ checkcoverage.
# ------------------------------------------------------------------
ask_inputs() {
  echo "KIỂM TRA MAC CŨ - 2 câu hỏi, không biết thì nhấn Enter để bỏ qua"
  echo
  echo "1) Ngày mua trên checkcoverage.apple.com (dd/mm/yyyy)."
  read -r -p "   Bỏ trống thì tool ước tính theo năm ra mắt (kém chính xác hơn): " ACT_IN
  read -r -p "2) Kiểm tra máy có thuộc công ty (Apple Business Manager)? Cần mật khẩu máy [y/N]: " DO_ABM
  ACT_TS=""
  if [ -n "$ACT_IN" ]; then
    ACT_TS=$(date -j -f "%d/%m/%Y %H:%M" "$ACT_IN 12:00" +%s 2>/dev/null)
    num "$ACT_TS" || { echo "  (ngày không đúng dạng dd/mm/yyyy, sẽ ước tính tuổi theo đời máy)"; ACT_TS=""; }
  fi
  ABM_OUT=""
  case "$DO_ABM" in
    y|Y|yes|có|co)
      echo "Nhập mật khẩu đăng nhập của máy (gõ không hiện ký tự là bình thường):"
      ABM_OUT=$(sudo /usr/bin/profiles show -type enrollment 2>&1)
      ;;
  esac
  echo
}

run_checks() {
  echo "Đang đọc thông tin máy (khoảng 10-30 giây)..."
  system_profiler -json SPHardwareDataType SPPowerDataType SPNVMeDataType SPStorageDataType > "$TMP/sp.json" 2>/dev/null
  sp() { plutil -extract "$1" raw -o - "$TMP/sp.json" 2>/dev/null; }

  SERIAL=$(sp SPHardwareDataType.0.serial_number)
  CHIP=$(sp SPHardwareDataType.0.chip_type)
  [ -z "$CHIP" ] && CHIP=$(sp SPHardwareDataType.0.cpu_type)
  RAM=$(sp SPHardwareDataType.0.physical_memory)
  MODEL=$(sp SPHardwareDataType.0.model_number)
  MODEL_ID=$(sp SPHardwareDataType.0.machine_model)
  MACHINE=$(sp SPHardwareDataType.0.machine_name)
  ALOCK=$(sp SPHardwareDataType.0.activation_lock_status)
  OSVER=$(sw_vers -productVersion); OSMAJOR=${OSVER%%.*}
  ARCH=$(uname -m)
  IS_LAPTOP=0; case "$MACHINE" in *Book*) IS_LAPTOP=1;; esac

  # Tên đầy đủ kèm năm, ví dụ "MacBook Pro (14-inch, Nov 2024)"
  PRODUCT=$(ioreg -arc IOPlatformDevice -k product-name 2>/dev/null | plutil -extract 0.product-name raw -o - - 2>/dev/null | base64 -D 2>/dev/null | tr -d '\000')
  [ -z "$PRODUCT" ] && PRODUCT="$MACHINE ($MODEL_ID)"
  REL_YEAR=$(echo "$PRODUCT" | grep -oE '(19|20)[0-9]{2}' | tail -1)
  REL_MON=7; REL_HAS_MON=0   # chỉ có năm thì lấy giữa năm
  for i in Jan:1 Feb:2 Mar:3 Apr:4 May:5 Jun:6 Jul:7 Aug:8 Sep:9 Oct:10 Nov:11 Dec:12; do
    echo "$PRODUCT" | grep -q "${i%%:*} " && { REL_MON=${i##*:}; REL_HAS_MON=1; }
  done

  # Pin
  B="SPPowerDataType.0.sppower_battery_health_info"
  CYCLES=$(sp $B.sppower_battery_cycle_count)
  BHEALTH=$(sp $B.sppower_battery_health)
  BMAX=$(sp $B.sppower_battery_health_maximum_capacity); BMAX=${BMAX%\%}
  BAT_IO=$(ioreg -rn AppleSmartBattery 2>/dev/null)
  MAXCYC=$(echo "$BAT_IO" | sed -nE 's/.*"DesignCycleCount9C" = ([0-9]+).*/\1/p' | head -1)
  num "$MAXCYC" || MAXCYC=1000
  if ! num "$BMAX"; then   # Intel đời cũ: tự tính từ dung lượng thực / thiết kế
    RAWMAX=$(echo "$BAT_IO" | sed -nE 's/.*"AppleRawMaxCapacity" = ([0-9]+).*/\1/p' | head -1)
    [ -z "$RAWMAX" ] && RAWMAX=$(echo "$BAT_IO" | sed -nE 's/.*"MaxCapacity" = ([0-9]+).*/\1/p' | head -1)
    DESIGN=$(echo "$BAT_IO" | sed -nE 's/.*"DesignCapacity" = ([0-9]+).*/\1/p' | head -1)
    if num "$RAWMAX" && num "$DESIGN" && [ "$DESIGN" -gt 0 ] && [ "$RAWMAX" -gt 100 ]; then
      BMAX=$(calc "$RAWMAX * 100 / $DESIGN" 0)
    fi
  fi

  # SSD
  SSD_BYTES=$(sp SPNVMeDataType.0._items.0.size_in_bytes)
  SMART_SP=$(sp SPNVMeDataType.0._items.0.smart_status)
  if ! num "$SSD_BYTES"; then
    SSD_BYTES=$(diskutil info -plist disk0 2>/dev/null | plutil -extract TotalSize raw -o - - 2>/dev/null)
    [ -z "$SMART_SP" ] && SMART_SP=$(diskutil info -plist disk0 2>/dev/null | plutil -extract SMARTStatus raw -o - - 2>/dev/null)
  fi

  MDM_OUT=$(profiles status -type enrollment 2>&1)
  SIP=$(csrutil status 2>/dev/null)

  # Kernel panic (máy tự khởi động lại vì lỗi) trong 6 tháng gần nhất
  PANICS=$(find /Library/Logs/DiagnosticReports -maxdepth 2 -name "*.panic" -mtime -180 2>/dev/null | wc -l | tr -d ' ')
  PANIC_LAST=$(ls -t /Library/Logs/DiagnosticReports/*.panic /Library/Logs/DiagnosticReports/Retired/*.panic 2>/dev/null | head -1)
  PANIC_READABLE=1; ls /Library/Logs/DiagnosticReports >/dev/null 2>&1 || PANIC_READABLE=0

  # S.M.A.R.T. SSD bằng smartctl đi kèm
  HAVE_SMART=0
  if [ -f "$DIR/smartctl" ]; then
    "$DIR/smartctl" -j -a disk0 > "$TMP/sm.json" 2>/dev/null
    plutil -extract nvme_smart_health_information_log.power_on_hours raw -o - "$TMP/sm.json" >/dev/null 2>&1 && HAVE_SMART=1
  fi
  sm() { plutil -extract "nvme_smart_health_information_log.$1" raw -o - "$TMP/sm.json" 2>/dev/null; }
  if [ $HAVE_SMART = 1 ]; then
    PU=$(sm percentage_used); DUW=$(sm data_units_written); POH=$(sm power_on_hours)
    PCYC=$(sm power_cycles); UNSAFE=$(sm unsafe_shutdowns); MEDIA=$(sm media_errors)
    ERRLOG=$(sm num_err_log_entries); SPARE=$(sm available_spare); SPARE_TH=$(sm available_spare_threshold)
    CW=$(sm critical_warning); TEMP=$(sm temperature); WTT=$(sm warning_temp_time); CTT=$(sm critical_comp_time)
    TBW=$(calc "${DUW:-0} * 512000 / 1000000000000" 1)
  fi

  # Tuổi máy: ưu tiên ngày kích hoạt, nếu không có thì tính từ ngày ra mắt (máy có thể trẻ hơn)
  NOW=$(date +%s)
  if num "$ACT_TS"; then
    MONTHS=$(calc "($NOW - $ACT_TS) / 86400 / 30.44" 1); AGE_SRC="theo ngày kích hoạt"
  elif num "$REL_YEAR"; then
    REL_TS=$(date -j -f "%Y-%m-%d %H:%M" "$REL_YEAR-$(printf %02d $REL_MON)-01 12:00" +%s 2>/dev/null)
    MONTHS=$(calc "($NOW - $REL_TS) / 86400 / 30.44" 1); AGE_SRC="ước tính từ lúc ra mắt; nhập ngày kích hoạt để chính xác hơn"
  fi

  # =================== ĐÁNH GIÁ ===================
  # 2. Khoá và quản lý
  case "$ALOCK" in
    *disabled*) ok "Activation Lock đã tắt";;
    *enabled*)  pend "Activation Lock đang BẬT: nhờ người bán vào System Settings → Apple ID → Sign Out (tắt Find My) rồi chạy lại. Người bán từ chối hoặc không nhớ mật khẩu Apple ID → BỎ máy";;
    *) if [ "$ARCH" = "arm64" ]; then warn "Không đọc được Activation Lock: xem System Information → Hardware"
       else INFO+=("Máy Intel không có chip T2 thì không có Activation Lock; thay vào đó hỏi người bán có đặt firmware password không"); fi;;
  esac
  if echo "$MDM_OUT" | grep -qE "(Enrolled via DEP|MDM enrollment): Yes"; then
    fail "Máy đang bị quản lý MDM (máy công ty / trường học): có thể bị khoá hoặc xoá từ xa"
  elif echo "$MDM_OUT" | grep -q "MDM enrollment: No"; then ok "Không bị quản lý MDM"
  else warn "Không đọc được MDM: xem System Settings → General → Device Management"; fi
  if [ -n "$ABM_OUT" ]; then
    if echo "$ABM_OUT" | grep -qiE "not DEP enabled|no.*configuration|Error fetching"; then
      ok "Máy không thuộc Apple Business/School Manager của công ty nào"
    elif echo "$ABM_OUT" | grep -qiE "ConfigurationURL|OrganizationName|IsMDMUnremovable|CloudConfig"; then
      fail "Máy được gán cho một tổ chức (Apple Business/School Manager): sau khi xoá máy sẽ bị bắt đăng ký MDM của công ty"
    elif echo "$ABM_OUT" | grep -qiE "incorrect password|Sorry|not in the sudoers"; then
      warn "Không kiểm tra được máy công ty (sai mật khẩu hoặc tài khoản không phải admin)"
    else warn "Chưa rõ kết quả kiểm tra máy công ty (cần Internet). Bước xoá máy cuối cùng sẽ xác nhận"; fi
  fi
  case "$SIP" in
    *enabled.*|*enabled) ok "Bảo mật hệ thống (SIP) đang bật";;
    *disabled*) warn "SIP đang TẮT: máy từng bị can thiệp hệ thống (bẻ khoá, cài macOS không chính thức...). Hỏi rõ lý do";;
  esac

  # 3. Còn được cập nhật macOS không
  if [ "$ARCH" != "arm64" ]; then
    warn "Máy Intel: macOS 26 Tahoe là bản cuối, không lên được macOS 27. Chỉ còn vá bảo mật thêm khoảng 1-2 năm, Xcode mới sẽ không chạy"
  else
    ok "Apple silicon: vẫn được cập nhật macOS mới"
    case "$CHIP" in *" M1"|*"M1 "*|*"M1") INFO+=("Chip M1 (2020-2021) là đời cũ nhất còn được hỗ trợ, sẽ bị bỏ sớm nhất trong dòng Apple silicon");; esac
  fi

  # 4. SSD
  if [ $HAVE_SMART = 1 ]; then
    if num "$CW" && [ "$CW" -ne 0 ]; then fail "SSD báo Critical Warning ($CW): ổ có vấn đề"; fi
    if num "$MEDIA" && [ "$MEDIA" -gt 0 ]; then fail "SSD có $MEDIA lỗi dữ liệu (Media Errors): ổ đang hỏng dần, SSD hàn chết nên thay rất đắt"; fi
    if num "$SPARE"; then
      if num "$SPARE_TH" && [ "$SPARE" -le "$SPARE_TH" ]; then fail "SSD hết vùng dự phòng (Available Spare $SPARE%)"
      elif [ "$SPARE" -lt 100 ]; then warn "SSD đã dùng tới vùng dự phòng (Available Spare $SPARE%)"; fi
    fi
    if num "$ERRLOG" && [ "$ERRLOG" -gt 0 ]; then warn "SSD có $ERRLOG mục trong nhật ký lỗi"; fi
    if num "$PU"; then
      if   [ "$PU" -ge 80 ]; then fail "SSD đã mòn $PU% tuổi thọ: sắp hết độ bền"
      elif [ "$PU" -ge 20 ]; then warn "SSD đã mòn $PU% tuổi thọ (dùng rất nặng, ép giá)"
      else ok "SSD mới mòn $PU% tuổi thọ"; fi
    fi
    if num "$UNSAFE" && [ "$UNSAFE" -gt 50 ]; then warn "Tắt máy đột ngột $UNSAFE lần (hay sập nguồn, hết pin đột ngột hoặc treo)"; fi
    if { num "$WTT" && [ "$WTT" -gt 0 ]; } || { num "$CTT" && [ "$CTT" -gt 0 ]; }; then
      warn "SSD từng chạy quá nhiệt (${WTT:-0} phút cảnh báo, ${CTT:-0} phút nguy hiểm)"
    fi
  else
    if [ -n "$SMART_SP" ] && [ "$SMART_SP" != "Verified" ]; then fail "macOS báo SSD có vấn đề (S.M.A.R.T.: $SMART_SP)"
    else warn "Không đọc được chi tiết SSD: mở app DriveDx để xem tay"; fi
  fi

  # 5. Kernel panic
  if [ $PANIC_READABLE = 1 ]; then
    if [ "$PANICS" -ge 3 ]; then fail "Máy bị kernel panic (tự sập, khởi động lại) $PANICS lần trong 6 tháng: dấu hiệu lỗi phần cứng/bo mạch"
    elif [ "$PANICS" -ge 1 ]; then warn "Có $PANICS lần kernel panic trong 6 tháng (lần gần nhất: $(basename "$PANIC_LAST" | sed -E 's/.*_([0-9]{4}-[0-9]{2}-[0-9]{2}).*/\1/')). Hỏi người bán"
    else ok "Không có kernel panic trong 6 tháng"; fi
  fi

  # 6. Pin (chỉ máy laptop)
  if [ $IS_LAPTOP = 1 ]; then
    case "$BHEALTH" in
      Good|Normal|"") ;;
      *) warn "macOS báo pin \"$BHEALTH\": cần thay pin → ép giá";;
    esac
    if num "$BMAX"; then
      # Chuẩn Apple: pin giữ ~80% dung lượng khi đạt số lần sạc thiết kế (thường 1000)
      EXP_BMAX=100; num "$CYCLES" && EXP_BMAX=$(calc "100 - 20 * $CYCLES / $MAXCYC" 0)
      if [ "$BMAX" -lt 80 ]; then warn "Pin còn $BMAX% (dưới mức 80% Apple khuyên thay) → trừ tiền thay pin"
      elif [ "$BMAX" -lt $((EXP_BMAX - 10)) ]; then warn "Pin còn $BMAX%, thấp hơn nhiều so với chuẩn (~${EXP_BMAX}% ở $CYCLES lần sạc): pin chai nhanh bất thường"
      else ok "Pin còn $BMAX% (chuẩn Apple ở $CYCLES lần sạc: ~${EXP_BMAX}%)"; fi
    fi
    if num "$CYCLES"; then
      if [ "$CYCLES" -ge "$MAXCYC" ]; then warn "Pin đã sạc $CYCLES lần, vượt mức thiết kế $MAXCYC lần → nên thay"
      elif [ "$CYCLES" -ge $((MAXCYC * 8 / 10)) ]; then warn "Pin đã sạc $CYCLES / $MAXCYC lần thiết kế: sắp hết vòng đời"
      else ok "Pin sạc $CYCLES / $MAXCYC lần thiết kế"; fi
      if num "$POH" && [ "$CYCLES" -lt 150 ] && [ "$POH" -gt 2500 ]; then
        warn "Chỉ $CYCLES lần sạc nhưng $POH giờ bật máy: máy gần như luôn cắm sạc, đã chạy rất nhiều"
      fi
    fi
  fi

  # 7. MỨC ĐỘ SỬ DỤNG so với mốc chuẩn (tính trên mỗi năm/tháng tuổi máy)
  LV_NAMES=("ÍT" "BÌNH THƯỜNG" "NHIỀU" "RẤT NHIỀU"); LV_RANK=0; LV_WHY=""
  add_usage() { # nhãn  giá-trị  đơn-vị  mốc1  mốc2  mốc3  [ref = chỉ tham khảo, không tính vào kết luận]
    local r=3
    if gt "$4" "$2"; then r=0; elif gt "$5" "$2"; then r=1; elif gt "$6" "$2"; then r=2; fi
    USAGE_LINES+=("$1: $2 $3 → ${LV_NAMES[$r]}  (ít <$4 | bình thường $4-$5 | nhiều $5-$6 | rất nhiều >$6)")
    [ "$7" = "ref" ] && return
    if [ "$r" -gt "$LV_RANK" ]; then LV_RANK=$r; LV_WHY="$1"; elif [ "$r" -eq "$LV_RANK" ] && [ "$r" -ge 2 ]; then LV_WHY="$LV_WHY, $1"; fi
  }
  if [ -n "$MONTHS" ] && gt "$MONTHS" 2; then
    YEARS=$(calc "$MONTHS / 12" 2)
    if [ $HAVE_SMART = 1 ]; then
      add_usage "Dữ liệu ghi vào SSD" "$(calc "$TBW / $YEARS" 1)" "TB/năm" 5 20 40
      # SSD của Apple chỉ đếm lúc ổ hoạt động, thường thấp hơn giờ dùng thật → chỉ tham khảo
      add_usage "Giờ SSD hoạt động (tham khảo)" "$(calc "${POH:-0} / $MONTHS" 0)" "giờ/tháng" 65 180 360 ref
      DAYS=$(calc "$MONTHS * 30.44" 0)
      AVG_LINE="~$(calc "${POH:-0} / $DAYS" 1) giờ SSD hoạt động/ngày (giờ dùng thật thường cao hơn), ghi ~$(calc "$TBW * 1000 / $DAYS" 0) GB/ngày"
    fi
    if [ $IS_LAPTOP = 1 ] && num "$CYCLES"; then
      add_usage "Số lần sạc pin" "$(calc "$CYCLES / $YEARS" 0)" "lần/năm" 100 250 365
      AVG_LINE="${AVG_LINE:+$AVG_LINE, }~$(calc "$CYCLES / $MONTHS" 1) lần sạc/tháng"
    fi
  fi

  # 8. DỰ KIẾN CÒN DÙNG ĐƯỢC (nếu tiếp tục dùng với cường độ như từ trước đến nay)
  THIS_YEAR=$(date +%Y); LIFE_LINES=()
  if num "$REL_YEAR"; then
    if [ "$ARCH" = "arm64" ]; then
      OS_LO=$((REL_YEAR + 6)); [ $OS_LO -lt $THIS_YEAR ] && OS_LO=$THIS_YEAR
      OS_HI=$((REL_YEAR + 8)); [ $OS_HI -le $OS_LO ] && OS_HI=$((OS_LO + 1))
      LIFE_LINES+=("macOS: còn nhận bản macOS lớn đến khoảng $OS_LO-$OS_HI, sau đó vá bảo mật thêm ~2 năm (ước tính, Apple không công bố)"$'\n'"     Làm iOS: Xcode mới cần macOS mới, nên hết dùng cho dev khoảng 1 năm sau bản macOS lớn cuối cùng")
      END_YEAR=$OS_HI; END_WHY="hỗ trợ macOS"
    else
      LIFE_LINES+=("macOS: đã dừng ở macOS 26 (2025), chỉ còn vá bảo mật đến khoảng 2027-2028. Xcode mới không chạy")
      END_YEAR=2027; END_WHY="hỗ trợ macOS (máy Intel)"
    fi
  fi
  if [ -n "$YEARS" ] && [ $HAVE_SMART = 1 ] && num "$PU"; then
    SSD_LEFT=$(calc "(100 - $PU) / (($PU + 1) / $YEARS)" 0)
    if [ "$SSD_LEFT" -gt 30 ]; then LIFE_LINES+=("SSD: còn trên 30 năm theo tốc độ ghi hiện tại → không phải giới hạn")
    else LIFE_LINES+=("SSD: còn khoảng $SSD_LEFT năm đến khi hết độ bền thiết kế (đến ~$((THIS_YEAR + SSD_LEFT)))")
      [ -z "$END_YEAR" ] || [ $((THIS_YEAR + SSD_LEFT)) -lt "$END_YEAR" ] && { END_YEAR=$((THIS_YEAR + SSD_LEFT)); END_WHY="độ bền SSD"; }
    fi
  fi
  if [ -n "$YEARS" ] && [ $IS_LAPTOP = 1 ] && num "$BMAX" && num "$CYCLES"; then
    if [ "$BMAX" -le 80 ]; then
      LIFE_LINES+=("Pin: đã tới mức nên thay (≤80%). Thay pin xong máy dùng tiếp bình thường")
    else
      LOSS=$((100 - BMAX)); BAT_LEFT=99
      [ $LOSS -gt 0 ] && BAT_LEFT=$(calc "($BMAX - 80) / ($LOSS / $YEARS)" 1)
      [ "$CYCLES" -gt 0 ] && { CYC_LEFT=$(calc "($MAXCYC - $CYCLES) / ($CYCLES / $YEARS)" 1); gt "$BAT_LEFT" "$CYC_LEFT" && BAT_LEFT=$CYC_LEFT; }
      if gt "$BAT_LEFT" 15; then LIFE_LINES+=("Pin: còn trên 15 năm mới xuống 80% → không phải giới hạn")
      else LIFE_LINES+=("Pin: còn khoảng $BAT_LEFT năm thì xuống 80% (~năm $(calc "$THIS_YEAR + $BAT_LEFT" 0)), lúc đó nên thay pin. Pin thay được, không phải hết đời máy"); fi
    fi
  fi
  [ -n "$END_YEAR" ] && LIFE_SUM="Máy (không tính pin vì thay được) còn dùng tốt đến khoảng năm $END_YEAR, giới hạn bởi: $END_WHY"
  if [ ${#USAGE_LINES[@]} -gt 0 ]; then
    USAGE="${LV_NAMES[$LV_RANK]}"
    case $LV_RANK in
      3) warn "Máy đã dùng RẤT NHIỀU (do: $LV_WHY). Không phải lỗi nhưng hao mòn cao → ép giá mạnh, hoặc tìm máy khác";;
      2) warn "Máy đã dùng NHIỀU (do: $LV_WHY). Không phải lỗi nhưng hao mòn hơn mức thường → nên ép giá";;
      *) ok "Mức dùng: $USAGE so với mốc chuẩn";;
    esac
  fi

  # Vùng
  REGION=$(echo "$MODEL" | sed -nE 's#.*[0-9]([A-Z]{1,2}/A)$#\1#p')
  [ "$REGION" = "J/A" ] && INFO+=("Bản Nhật: bàn phím JIS (phím ¥, Return chữ L, có phím 英数/かな)")
  case "$MODEL" in Z*) INFO+=("Mã bắt đầu bằng Z: máy đặt cấu hình riêng (CTO)");; esac

  SSD_NOMINAL="?"
  if num "$SSD_BYTES"; then
    SSD_GB_REAL=$(calc "$SSD_BYTES / 1000000000" 0)
    SSD_NOMINAL=$(awk -v g="$SSD_GB_REAL" 'BEGIN{n=128; while (n*1.15 < g) n*=2; print n}')
  fi

  # =================== IN BÁO CÁO ===================
  echo
  echo "======================================================"
  echo "  BÁO CÁO KIỂM TRA MAC  -  $(date '+%d/%m/%Y %H:%M')"
  echo "======================================================"
  echo "Máy        : $PRODUCT"
  echo "Cấu hình   : $CHIP - RAM $RAM - SSD ${SSD_NOMINAL} GB - macOS $OSVER"
  echo "             → SO VỚI TIN ĐĂNG BÁN: chip, RAM, SSD phải khớp"
  echo "Serial     : $SERIAL"
  echo "Model      : $MODEL ($MODEL_ID)  →  bản $(region_name "$REGION")"
  echo "Khoá       : Activation Lock ${ALOCK#activation_lock_}"
  [ $IS_LAPTOP = 1 ] && echo "Pin        : $CYCLES / $MAXCYC lần sạc, còn ${BMAX:-?}%, ${BHEALTH:-?}"
  if [ $HAVE_SMART = 1 ]; then
    echo "SSD        : mòn ${PU}%, đã ghi ${TBW} TB, ${POH} giờ bật, ${PCYC} lần bật/tắt"
    echo "             ${UNSAFE} lần tắt đột ngột, ${MEDIA} lỗi dữ liệu, dự phòng ${SPARE}%, ${TEMP}°C"
  fi
  [ -n "$MONTHS" ] && echo "Tuổi máy   : ~${MONTHS} tháng (${AGE_SRC})"
  if [ ${#USAGE_LINES[@]} -gt 0 ]; then
    echo "Mức dùng   : $USAGE  (lấy mức cao nhất trong các chỉ số dưới đây)"
    for m in "${USAGE_LINES[@]}"; do echo "   • $m"; done
    [ -n "$AVG_LINE" ] && echo "Trung bình : $AVG_LINE"
  fi
  if [ ${#LIFE_LINES[@]} -gt 0 ]; then
    echo "Còn dùng được (nếu dùng như từ trước đến nay):"
    for m in "${LIFE_LINES[@]}"; do echo "   • $m"; done
    [ -n "$LIFE_SUM" ] && echo "   → $LIFE_SUM"
  fi
  echo "------------------------------------------------------"
  if [ ${#FAILS[@]} -gt 0 ]; then
    echo "KẾT LUẬN:  ❌ KHÔNG NÊN MUA"
  elif [ ${#PENDS[@]} -gt 0 ]; then
    echo "KẾT LUẬN:  ⏸  CHƯA MUA ĐƯỢC - người bán cần xử lý dòng ⏸ rồi chạy lại tool"
  elif [ ${#WARNS[@]} -gt 0 ]; then
    echo "KẾT LUẬN:  ⚠️  MUA ĐƯỢC NHƯNG CẦN CÂN NHẮC / ÉP GIÁ"
  else
    echo "KẾT LUẬN:  ✅ NÊN MUA (phần kiểm tra tự động đều đạt)"
  fi
  echo "------------------------------------------------------"
  for m in "${FAILS[@]}"; do echo "  ❌ $m"; done
  for m in "${PENDS[@]}"; do echo "  ⏸  $m"; done
  for m in "${WARNS[@]}"; do echo "  ⚠️  $m"; done
  for m in "${OKS[@]}";   do echo "  ✅ $m"; done
  for m in "${INFO[@]}";  do echo "  ℹ️  $m"; done
  echo
  echo "TỰ KIỂM TRA TAY (tool không đo được):"
  echo "  [ ] So chip / RAM / SSD / màu máy với tin đăng bán"
  echo "  [ ] Serial (ở trên, đáy máy, hộp) và số lần sạc khớp với tin đăng / ảnh người bán gửi"
  if [ "$ARCH" = "arm64" ] && [ "${OSMAJOR:-0}" -ge 26 ]; then
    echo "  [ ] System Settings → General → About: nếu có mục \"Parts & Service\" là máy đã sửa."
    echo "      Mở xem: \"Unknown\" (linh kiện không rõ) hoặc \"Used\" (linh kiện tháo máy khác) → ép giá / bỏ"
  fi
  echo "  [ ] Màn hình: ảnh trắng/đen/đỏ/xanh toàn màn hình, không điểm chết, không bong lớp phủ"
  [ $IS_LAPTOP = 1 ] && echo "  [ ] Bàn phím gõ hết phím + đèn nền, Touch ID thêm được vân tay, trackpad click đều 4 góc"
  echo "  [ ] Loa to không rè, mic (Voice Memos), camera (Photo Booth), Wi-Fi, Bluetooth"
  echo "  [ ] Cắm sạc và thử từng cổng (USB-C/Thunderbolt, HDMI, khe SD, jack tai nghe)"
  echo "  [ ] Vỏ không móp, ốc đáy không toét, bản lề chắc"
  echo "  [ ] (Tuỳ chọn) Apple Diagnostics: tắt máy, giữ nút nguồn đến khi hiện Options, bấm Cmd+D"
  echo "  [ ] CUỐI CÙNG: Erase All Content and Settings → cài đặt đến bước Wi-Fi:"
  echo "      không hỏi Apple ID chủ cũ, không hiện \"Remote Management\" mới trả tiền"
}

clear
ask_inputs
OUT_NAME="KetQua-$(date +%Y%m%d-%H%M).txt"
if touch "$DIR/$OUT_NAME" 2>/dev/null; then OUT="$DIR/$OUT_NAME"; else OUT="$HOME/Desktop/$OUT_NAME"; fi
run_checks 2>/dev/null | tee "$OUT"
echo
echo "Đã lưu báo cáo: $OUT"
read -n 1 -s -r -p "Nhấn phím bất kỳ để đóng..."
echo
