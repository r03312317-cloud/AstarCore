from pathlib import Path
r=Path(__file__).resolve().parent
s=(r/'sim/linux_soc_main.cpp').read_text()
marker=' Verilated::commandArgs(argc,argv);Vrv32_linux_soc_top d;'
assert s.count(marker)==1
s=s.replace(marker,marker+'''\n std::ofstream raw_uart;if(const char*p=std::getenv("RV32_UART_CAPTURE")){raw_uart.open(p,std::ios::binary);if(!raw_uart)throw std::runtime_error("UART capture open failed");}''')
marker='std::cout<<char(txbyte)<<std::flush;terminal.observe(txbyte);'
assert s.count(marker)==1
s=s.replace(marker,marker+'if(raw_uart.is_open()){raw_uart.put(char(txbyte));raw_uart.flush();}')
(r/'sim/linux_soc_capture.cpp').write_text(s,encoding='utf-8')
print('Added independent raw UART capture to a separate fixture copy.')
