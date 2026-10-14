import hilog from '@ohos.hilog';

export class StringBuffer {
    private mSurface: string;

    constructor() {
        this.mSurface = ""
    }

    public clear() {
        this.mSurface.slice(0);
    }

    public delete(start?: number, end?: number) {
        if (start >= 0 && start <= this.mSurface.length) {
            this.mSurface = this.mSurface.substring(0, start) + this.mSurface.substring(end);
        }
    }

    public insert(pos: number, ch: string) {
        if (pos >= 0 && pos <= this.mSurface.length) {
            this.mSurface = this.mSurface.substring(0, pos) + ch + this.mSurface.substring(pos);
        }
    }

    public replace(from: number, length: number, replace: string) {
        if (from >= 0 && from + length <= this.mSurface.length) {
            this.mSurface = this.mSurface.substring(0, from) + replace + this.mSurface.substring(from + length);
        }
    }

    public charAt(pos: number): string {
        if (pos >= 0 && pos <= this.mSurface.length) {
            return this.mSurface.charAt(pos);
        }
        return '';
    }

    public substring(start: number, end?: number): string {
        return this.mSurface.substring(start, end);
    }

    public substr(from: number, length?: number): string {
        return this.mSurface.substr(from, length);
    }

    public length(): number {
        return this.mSurface.length;
    }

    public buffer(): string {
        return this.mSurface;
    }
}