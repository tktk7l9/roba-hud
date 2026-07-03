import Foundation

/// Embedded copies of the real zmk-config-roBa files, used by --selftest so
/// tests run in CI without the zmk-config checkout. If the real keymap
/// changes shape, refresh these from the repo.
enum Fixtures {
    static let keymap = """
#include <behaviors.dtsi>
#include <dt-bindings/zmk/bt.h>
#include <dt-bindings/zmk/outputs.h>
#include <dt-bindings/zmk/keys.h>
#include <dt-bindings/zmk/pointing.h>

// Ported from the Keyball39 (remap-keys.app) cheat sheet to the roBa layout.
// roBa keeps its trackball features: auto-mouse on layer 4, scroll on layer 5.

&mt {
    flavor = "balanced";
    quick-tap-ms = <0>;
};

&lt {
    flavor = "balanced";
    quick-tap-ms = <175>;
    tapping-term-ms = <200>;
};

&trackball {
    automouse-layer = <4>;
    scroll-layers = <5>;
};

/ {
    behaviors {
        // BTclr 誤爆防止: 0.5秒ホールドで発動、タップ(誤爆)は無反応(&none)
        // BT_CLR は2トークンに展開され &bt は2セル必要。hold-tap の hold 側は
        // 1パラメータしか渡せないため、マクロ(bt_clr_macro)経由で &bt BT_CLR を呼ぶ。
        bt_clr_hold: bt_clr_hold {
            compatible = "zmk,behavior-hold-tap";
            #binding-cells = <2>;
            flavor = "tap-preferred";
            tapping-term-ms = <500>;
            bindings = <&bt_clr_macro>, <&none>;
        };

        // マーカー付きレイヤータップ (&lt 互換・第1パラメータはダミー 0)。
        // 使い方: &ltm2 0 SPACE = タップで Space / ホールドで NUM + F22 マーカー。
        // フレーバー/タイミングは従来の &lt 設定と同値。
        ltm1: ltm1 {
            compatible = "zmk,behavior-hold-tap";
            #binding-cells = <2>;
            flavor = "balanced";
            tapping-term-ms = <200>;
            quick-tap-ms = <175>;
            bindings = <&mkr_l1>, <&kp>;
        };
        ltm2: ltm2 {
            compatible = "zmk,behavior-hold-tap";
            #binding-cells = <2>;
            flavor = "balanced";
            tapping-term-ms = <200>;
            quick-tap-ms = <175>;
            bindings = <&mkr_l2>, <&kp>;
        };
        ltm3: ltm3 {
            compatible = "zmk,behavior-hold-tap";
            #binding-cells = <2>;
            flavor = "balanced";
            tapping-term-ms = <200>;
            quick-tap-ms = <175>;
            bindings = <&mkr_l3>, <&kp>;
        };
        ltm5: ltm5 {
            compatible = "zmk,behavior-hold-tap";
            #binding-cells = <2>;
            flavor = "balanced";
            tapping-term-ms = <200>;
            quick-tap-ms = <175>;
            bindings = <&mkr_l5>, <&kp>;
        };
    };

    macros {
        bt_clr_macro: bt_clr_macro {
            compatible = "zmk,behavior-macro";
            #binding-cells = <0>;
            bindings = <&bt BT_CLR>;
        };

        // レイヤーマーカー: レイヤーを有効化しつつ F21-F24 をホールド区間だけ押す。
        // F21+ は macOS に仮想キーコードが無く OS からは不可視。roba-hud だけが
        // 生 HID (IOHIDManager) で受信し、表示レイヤーの正確な切替に使う。
        // 対応表: F21=SYMBOL(1) / F22=NUM(2) / F23=FUNC(3) / F24=SCROLL(5)
        mkr_l1: mkr_l1 {
            compatible = "zmk,behavior-macro";
            #binding-cells = <0>;
            wait-ms = <0>;
            tap-ms = <0>;
            bindings = <&macro_press &mo 1 &kp F21>,
                       <&macro_pause_for_release>,
                       <&macro_release &mo 1 &kp F21>;
        };
        mkr_l2: mkr_l2 {
            compatible = "zmk,behavior-macro";
            #binding-cells = <0>;
            wait-ms = <0>;
            tap-ms = <0>;
            bindings = <&macro_press &mo 2 &kp F22>,
                       <&macro_pause_for_release>,
                       <&macro_release &mo 2 &kp F22>;
        };
        mkr_l3: mkr_l3 {
            compatible = "zmk,behavior-macro";
            #binding-cells = <0>;
            wait-ms = <0>;
            tap-ms = <0>;
            bindings = <&macro_press &mo 3 &kp F23>,
                       <&macro_pause_for_release>,
                       <&macro_release &mo 3 &kp F23>;
        };
        mkr_l5: mkr_l5 {
            compatible = "zmk,behavior-macro";
            #binding-cells = <0>;
            wait-ms = <0>;
            tap-ms = <0>;
            bindings = <&macro_press &mo 5 &kp F24>,
                       <&macro_pause_for_release>,
                       <&macro_release &mo 5 &kp F24>;
        };
    };

    keymap {
        compatible = "zmk,keymap";

        default_layer {
            display-name = "BASE";
            bindings = <
&kp Q     &kp W     &kp E     &kp R          &kp T                                          &kp Y               &kp U          &kp I      &kp O     &kp P
&kp A     &kp S     &kp D     &kp F          &kp G       &mkr_l5                &mkp MB3     &kp H               &kp J          &kp K      &kp L     &kp ENTER
&kp Z     &kp X     &kp C     &kp V          &kp B       &kp DEL                &caps_word   &kp N               &kp M          &mkp MB1  &mkp MB2  &mt LSHFT MINUS
&kp LGUI  &kp COMMA &kp DOT   &ltm1 0 TAB    &ltm2 0 SPACE &ltm5 0 LANG2        &mt LCTRL LANG1  &kp BACKSPACE                                       &ltm3 0 ESC
            >;

            sensor-bindings = <&inc_dec_kp PG_UP PAGE_DOWN>;
        };

        symbol_layer {
            display-name = "SYMBOL";
            bindings = <
&kp PERCENT  &kp DOLLAR  &kp AMPERSAND  &kp CARET    &kp SLASH                       &kp BACKSLASH  &kp LEFT_BRACE        &kp RIGHT_BRACE       &kp LESS_THAN  &kp GREATER_THAN
&kp AT_SIGN  &kp UNDER   &kp ASTERISK   &kp PLUS     &kp EQUAL    &trans      &trans  &kp UNDER      &kp LEFT_PARENTHESIS  &kp RIGHT_PARENTHESIS &kp SEMICOLON  &kp COLON
&kp GRAVE    &kp TILDE   &kp HASH       &kp EXCL     &kp QMARK    &trans      &trans  &kp PIPE       &kp LEFT_BRACKET      &kp RIGHT_BRACKET     &kp SQT        &kp DQT
&trans       &trans      &trans         &trans       &trans       &trans      &trans  &trans                                                                    &trans
            >;
        };

        num_layer {
            display-name = "NUM";
            bindings = <
&to 0            &kp KP_NUMBER_7  &kp KP_NUMBER_8  &kp KP_NUMBER_9  &kp KP_DIVIDE                       &kp ENTER       &kp HOME        &kp UP_ARROW    &kp END          &kp LALT
&kp KP_NUMBER_0  &kp KP_NUMBER_4  &kp KP_NUMBER_5  &kp KP_NUMBER_6  &kp KP_MULTIPLY  &kp KP_MINUS  &trans     &kp PG_UP       &kp LEFT_ARROW  &kp DOWN_ARROW  &kp RIGHT_ARROW  &kp PG_DN
&kp KP_DOT       &kp KP_NUMBER_1  &kp KP_NUMBER_2  &kp KP_NUMBER_3  &kp LSHFT        &kp KP_PLUS   &trans     &kp LA(LEFT)    &kp LA(RIGHT)   &mkp MB1       &mkp MB2         &mkp MB3
&kp LGUI         &trans           &trans           &trans           &trans           &trans        &kp LCTRL  &kp DEL                                                          &mkr_l3
            >;
        };

        function_layer {
            display-name = "FUNC";
            bindings = <
&out OUT_TOG  &kp F7  &kp F8  &kp F9  &kp F10                                  &kp C_PREV     &kp C_PP       &kp C_NEXT    &kp C_MUTE     &bt_clr_hold 0 0
&sys_reset    &kp F4  &kp F5  &kp F6  &kp F11  &trans         &trans     &kp C_VOL_DN   &kp C_VOL_UP   &kp LG(LS(N4))  &kp C_BRI_UP   &bt BT_SEL 1
&trans        &kp F1  &kp F2  &kp F3  &kp F12  &trans         &trans     &kp LA(LEFT)   &kp LA(RIGHT)  &kp C_BRI_DN  &kp LC(LG(LS(N4)))   &bt BT_SEL 0
&trans        &trans  &trans  &trans  &trans   &trans         &kp LCTRL  &trans                                                     &bootloader
            >;
        };

        mouse_layer {
            display-name = "MOUSE";
            bindings = <
&trans  &trans  &trans  &trans  &trans                      &trans  &trans  &trans     &trans     &trans
&trans  &trans  &trans  &trans  &trans  &trans      &trans  &trans  &trans  &trans     &trans     &trans
&trans  &trans  &trans  &trans  &trans  &trans      &trans  &trans  &trans  &mkp MB1  &mkp MB2   &mkp MB3
&trans  &trans  &trans  &trans  &trans  &trans      &trans  &trans                                &trans
            >;
        };

        scroll_layer {
            display-name = "SCROLL";
            bindings = <
&trans  &trans  &trans  &trans  &trans                      &trans  &trans  &trans  &trans  &trans
&trans  &trans  &trans  &trans  &trans  &trans      &trans  &trans  &trans  &trans  &trans  &trans
&trans  &trans  &trans  &trans  &trans  &trans      &trans  &trans  &trans  &trans  &trans  &trans
&trans  &trans  &trans  &trans  &trans  &trans      &trans  &trans                          &trans
            >;
        };
    };
};
"""

    static let layoutJSON = """
{
  "layouts": {
    "default_layout": {
      "name": "default_layout",
      "layout": [
        { "row": 0, "col":  0, "x":      0, "y": 0.616 },
        { "row": 0, "col":  1, "x":  1.003, "y": 0.247 },
        { "row": 0, "col":  2, "x":  2.005, "y":     0 },
        { "row": 0, "col":  3, "x":  3.008, "y": 0.132 },
        { "row": 0, "col":  4, "x":  4.011, "y": 0.263 },
        { "row": 0, "col":  9, "x":  8.504, "y": 0.264 },
        { "row": 0, "col": 10, "x":  9.506, "y": 0.133 },
        { "row": 0, "col": 11, "x": 10.509, "y": 0.001 },
        { "row": 0, "col": 12, "x": 11.512, "y": 0.248 },
        { "row": 0, "col": 13, "x": 12.514, "y": 0.617 },

        { "row": 1, "col":  0, "x":      0, "y": 1.618 },
        { "row": 1, "col":  1, "x":  1.003, "y":  1.25 },
        { "row": 1, "col":  2, "x":  2.005, "y": 1.003 },
        { "row": 1, "col":  3, "x":  3.008, "y": 1.134 },
        { "row": 1, "col":  4, "x":  4.011, "y": 1.266 },
        { "row": 1, "col":  5, "x":  5.015, "y": 1.504 },
        { "row": 1, "col":  8, "x":  7.501, "y": 1.505 },
        { "row": 1, "col":  9, "x":  8.504, "y": 1.267 },
        { "row": 1, "col": 10, "x":  9.506, "y": 1.135 },
        { "row": 1, "col": 11, "x": 10.509, "y": 1.004 },
        { "row": 1, "col": 12, "x": 11.512, "y": 1.251 },
        { "row": 1, "col": 13, "x": 12.514, "y": 1.619 },

        { "row": 2, "col":  0, "x":      0, "y": 2.621 },
        { "row": 2, "col":  1, "x":  1.003, "y": 2.253 },
        { "row": 2, "col":  2, "x":  2.005, "y": 2.005 },
        { "row": 2, "col":  3, "x":  3.008, "y": 2.137 },
        { "row": 2, "col":  4, "x":  4.011, "y": 2.268 },
        { "row": 2, "col":  5, "x":  5.013, "y": 2.507 },
        { "row": 2, "col":  8, "x":  7.501, "y": 2.508 },
        { "row": 2, "col":  9, "x":  8.504, "y": 2.269 },
        { "row": 2, "col": 10, "x":  9.506, "y": 2.138 },
        { "row": 2, "col": 11, "x": 10.509, "y": 2.006 },
        { "row": 2, "col": 12, "x": 11.512, "y": 2.254 },
        { "row": 2, "col": 13, "x": 12.514, "y": 2.622 },

        { "row": 3, "col":  0, "x":      0, "y": 3.624 },
        { "row": 3, "col":  1, "x":  1.003, "y": 3.255 },
        { "row": 3, "col":  2, "x":  2.004, "y": 3.007 },
        { "row": 3, "col":  3, "x":  3.219, "y": 3.525 },
        { "row": 3, "col":  4, "x":  4.342, "y": 3.617, "r":   9, "rx": 4.842, "ry": 4.117 },
        { "row": 3, "col":  5, "x":  5.451, "y": 3.909, "r":  20, "rx": 5.951, "ry": 4.409 },
        { "row": 3, "col":  8, "x":  7.059, "y":  3.91, "r": -20, "rx": 7.559, "ry":  4.41 },
        { "row": 3, "col":  9, "x":  8.158, "y": 3.616, "r": -10, "rx": 8.658, "ry": 4.116 },
        { "row": 3, "col": 13, "x": 12.514, "y": 3.625 }
      ]
    }
  }
}
"""
}
