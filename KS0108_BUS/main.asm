.include "m8515def.inc"	;Подключаем заголовочный файл

;KS0108 LCD----------------------------------------------------------------------------------
;Для работы с lcd используется внешнее адресное пространство (старшие 32кб)
;Распиновка указана на схеме (Release\lcd.DSN), частота микроконтроллера - до 2MHz
;При вызове функций r16, r17, r30, r31 используются как аккумулятор (см. описание функций) 
;
;Управляющие сигналы (шина адреса)
;c - номер чипа (0 - оба чипа),
;p, b - номера страницы и байта соответственно
.equ	WRCD	= 0x80	;Пишем команду		(+c)
.equ	WRDT	= 0x88	;Пишем данные		(+c)
.equ	RDDT	= 0x8C	;Читаем данные		(+c обязательно!!!)
.equ	RDCD	= 0x84	;Читаем состояние	(+c обязательно!!!)
;Передаваймые команды (шина данных)
.equ	STPG	= 0xB8	;Задать страницу	(+p)
.equ	STNM	= 0x40	;Задать номер байта	(+b)
.equ	SCRL	= 0xC0	;Команда скроллинга	(+номер строки 0 - 63)
.equ	ONOF	= 0x3E	;Команда отображения(+1 - включить, +0 выключить)

.cseg
.org 0

;Таблица прерываний
rjmp	Init	; Reset Handler
reti			; IRQ0 Handler
reti			; IRQ1 Handler
reti			; Timer1 Capture Handler
reti			; Timer1 CompareA Handler
reti			; Timer1 CompareB Handler
reti			; Timer1 Overflow Handler
reti			; Timer0 Overflow Handler
reti			; SPI Transfer Complete Handler
reti			; UART RX Complete Handler
reti			; UDR Empty Handler
reti			; UART TX Complete Handler
reti			; Analog Comparator Handler

;Нчальная инициализация 
Init:                  
	ldi r16, High(RAMEND)	;Задаем SP
	out SPH, r16
	ldi r30, Low(RAMEND)
	out SPL, r16
	clr r16
rjmp Gen					;Переходим к главной программе

;Задержка на 12 циклов
WaitMcs:
	nop
	nop
	nop
	nop
	nop
ret

;LCD
;--------------------------------------------------------------------------------------------
;Инициализация портов для работы с lcd
LcdPortsInit:
	ldi r16, 0xA0	;Включаем внешнее адресное пространство
	ori r16, MCUCR	;с дефолтными циклами чтения/записи
	out MCUCR, r16	;и спящий режим
	ldi r16, 0x01	;Конфигурируем PORTE
	out DDRE, r16
	out PORTE, r16	;RST=1
	clr r16
ret

;Сброс lcd
LcdRst:
	cbi PORTE, 0	;RST=0
	rcall WaitMcs	;Ждем
	sbi PORTE, 0	;RST=1
ret

;Инициализация lcd
LcdInit:
	rcall LcdPortsInit	;Инициализация портов
	rcall LcdRst		;Сброс
	ldi r16, ONOF+1		;Команда включения отображения
	sts WRCD<<8, r16	;Включим отображение
	ldi r16, SCRL		;Команда скроллинга к 0 строке
	sts WRCD<<8, r16	;Скроллинг вверх
	clr r16
ret

;Задать адрес байта
;IN:
;r17 - X = Номер байта (0 - 127)
;r30 - Y = Номер страницы (0 - 7)
;OUT:
;r31 - Номер выбранного для записи команды чипа (1 или 2 исходя из номера байта)
LcdByteSetXY:
	ldi r31, WRCD	;Кладем в r31 команду записи команды
	sbrc r17, 6		;Если номер страницы > 63,
	inc r31			;то пишем в второй чип,
	inc r31			;иначе - в первый
	ori r17, STNM	;Пишем номер байта
	st Z, r17		;Отправили команду
	ori r30, STPG	;Пишем номер страницы	
	st Z, r30		;Отправили команду
	andi r30, 0x07	;Восстановим номер страницы	
	sbrc r31,0		;Восстановим номер байта
	andi r17, 0x3F	
	andi r31, 0x03	;Оставим в r31 только номер чипа
ret

;Запись байта в lcd
;IN:
;r16 - Данные
;r17 - Номер байта (0 - 127)
;r30 - Номер страницы (0 - 7)
LcdWriteByte:
	rcall LcdByteSetXY	;Задаем байт и страницу
	ori r31, WRDT		;Команда записи данных
	st Z, r16			;Записываем сам байт
ret

;Чтение байта
;IN:
;r17 - Номер байта (0 - 127)
;r30 - Номер страницы (0 - 7)
;OUT:
;r16 - Значение байта
LcdReadByte:
	rcall LcdByteSetXY	;Задаем байт и страницу
	ori r31, RDDT		;Команда чтения данных
	ld r16, Z			;Считываем байт два раза, т.к. 
	ld r16, Z			;экраничик требует для чтения данных двойной строб
ret

;Заливка экрана
;IN:
;r16 - Заливающий байт
LcdFill:
	ldi r30, 0x07	;Счетчик на 8 страниц
	loopY:			;Цикл перебора страниц (строк)
		ldi r17, 0x7F		;Счетчик байт на 128
		loopX:				;Цикл перебора байт (столбцов)
			rcall LcdWriteByte	;Пишем даннные по выставленному адресу (r30, r17)
			rcall LcdReadByte	;для проверки считываем данные по тому же адресу !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
			dec r17				;Декремент счетчика байт
			brpl loopX			;и проверка на выход из цикла
		dec r30			;Декремент счетчика страниц
		brpl loopY		;и проверка на выход из цикла
ret
;--------------------------------------------------------------------------------------------

;Основная прогррамма
Gen:
	rcall LcdInit			;Инициализация экранчика

	;Пример работы

	;Заливка
	ldi r16, 0xF0			;Заливающий байт (каждая страница будет наполовину черной)	
	rcall LcdFill			;Заливаем

	;Чтение/запись данных
	ldi r16, 0xAA			;Байт на запись
	ldi r17, 0x01			;Номер байта - 1
	ldi r30, 0x01			;Номер страницы - 1
	rcall LcdWriteByte		;Запишем байт в экранчик
	rcall LcdWriteByte		;Можем писать байты подряд, без задержек между вызовами функции
	rcall LcdReadByte		;Прочитаем этот же байт r16 уже из памяти экранчика
	rcall LcdReadByte		;Можем читать байты подряд, без задержек между вызовами функции
	ldi r17, 0x54			;Зададим новый номер байта - 54
	ldi r30, 0x03			;и новый номер страницы - 3
	rcall LcdWriteByte		;Выведем, записанный ранее в r16 байт, на экран
	
	;Чтение/запись команд
	lds r16, RDCD+1<<8		;Читаем состояние первого чипа в r16
	rcall WaitMcs			;Читаем состояния, с задержеками между вызовами функции
	lds r17, RDCD+2<<8		;Читаем состояние второго чипа в r17
	rcall WaitMcs			;Не забываем про задержку
	;скроллинг
	ldi r16, SCRL+15		;Будем скроллить на 15 строк вверх
	sts WRCD+1<<8, r16		;Скроллинг
	ldi r16, SCRL+5			;Скроллить можно без задержки
	sts WRCD+1<<8, r16		;Скроллинг на 5 строк вверх

END: rjmp END	;Конец основной программы