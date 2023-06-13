BOOT_AND_SYSTEM_SIZE = 0x200+0x7C00-0x600 # 7800, 3c sectors
BOOTSTRAP_SIZE = 0x200
USER_LIMIT = 0x3000

boot_and_system = open("system.bin", "rb").read()
fs = open("fs.img", "rb").read()
shell = open("print_digits.bin", "rb").read()
#user1 = open("print_letters.bin", "rb").read()

img = ""
img += boot_and_system + bytearray([0] * (BOOT_AND_SYSTEM_SIZE - len(boot_and_system)))
img += fs
img += shell + bytearray([0] * USER_LIMIT)
#img += user1 + bytearray([0] * USER_LIMIT)

with open("img.img", "wb") as out_file:
  out_file.write(img)

