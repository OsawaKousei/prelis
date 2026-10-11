import type {IconName} from '@prelis/icons';
import arrow from '@prelis/icons/assets/arrow.png';
import check from '@prelis/icons/assets/check.png';
import close from '@prelis/icons/assets/close.png';
import diary from '@prelis/icons/assets/diary.png';
import home from '@prelis/icons/assets/home.png';
import left from '@prelis/icons/assets/left.png';
import password from '@prelis/icons/assets/password.png';
import right from '@prelis/icons/assets/right.png';
import save from '@prelis/icons/assets/save.png';
import timer from '@prelis/icons/assets/timer.png';

const images: Record<IconName, string> = {arrow, check, close, diary, home, left, password, right, save, timer};

export const Icon = ({
  name,
  size = 20,
}: {
  readonly name: IconName;
  readonly size?: number;
}) => (
  <span
    aria-hidden="true"
    className="prelis-icon"
    style={{width: size, height: size, maskImage: `url(${images[name]})`, WebkitMaskImage: `url(${images[name]})`}}
  />
);
