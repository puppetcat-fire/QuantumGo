#include <stdio.h>
#include <stdlib.h>
#include <windows.h>
#include <conio.h>
#include <process.h>
#include <time.h>
// 棋子类型
typedef enum State
{
    BLACK = -1,
    BLANK,
    WHITE,

} State;
typedef enum SURRENDER
{
    UNSURRENDER = 0, // 默认，双方未投降
    BLACKSURRENDER,  // 黑棋投降
    WHITESURRENDER,  // 白棋投降
    BOTHSURRENDER    // 都投降
} SURRENDER;
typedef enum WINNER
{
    BLACKISWINNER = -1,
    UNKNOW,
    WHITEISWINNER,

} WINNER;
// 单个棋子
typedef struct Piece
{
    struct Piece *up;    // 指向该子上方的子
    struct Piece *down;  // 指向该子下方的子
    struct Piece *left;  // 指向该子左方的子
    struct Piece *right; // 指向该子右方的子
    State state;         // 该棋子状态黑-白-空
    int mesh;            // 目数
    int qi;              // 该棋子的气（这里的气的统计没有排除共子的情况，只作于统计活路以及提子）
    int exist;           // 量子特性，存在？
} Piece;
// 黑白两个独立线程的数据结构体
typedef struct MultiThreadData
{
    int signMoveChessboard; // 棋盘编号
    int positionI;          // 落子位置i
    int positionJ;          // 落子位置j
    int positionILast;      // 量子落子位a-i
    int positionJLast;      // 量子落子位a-j
    int signMove;           // 落子行为标志量
    int signMoveQuantum;    // 落子行为标志量
    int positionMax;        // 棋盘大小Max*Max
    int iswin;
} MultiThreadData;
typedef struct ChessBoardData
{
    int chessBoardN;                     // 棋盘编号
    int step;                            // 当前步数，还没写，需要保证每个棋盘步数一致，不一致会导致需要回到上一步。或者按父亲到孩子依次输入？可以规避掉回退，但是会导致选手察觉到某个棋盘是真。
    int probability;                     // 当前可能性
    int probabilityBase;                 // 基础可能性，用于当当前棋盘被提虚子，而仍存在大量子棋盘集的情况。
    int jiezhengi[2];                    // 劫争i,0白1黑
    int jiezhengj[2];                    // 劫争j,0白1黑
    int meshBlack;                       // 黑气总数
    int meshWhite;                       // 白气总数
    int childrenSum;                     // 孩子总数
    int fakepieceI;                      // 虚假棋子提子i。
    int fakepieceJ;                      // 虚假棋子j。
    State state;                         // 当前是谁的回合
    SURRENDER IFOneissurrender;          // 投降标志位。
    Piece **chessBoard;                  // 指向具体棋盘
    struct ChessBoardData *whiteRight;   // 白棋棋盘链表指针
    struct ChessBoardData *whiteLeft;    // 白棋棋盘链表指针
    struct ChessBoardData *blackRight;   // 黑棋棋盘链表指针
    struct ChessBoardData *blackLeft;    // 黑棋棋盘链表指针
    struct ChessBoardData *father;       // 指向存在的棋盘，在提子后将概率返回父节点（步数）。
    struct ChessBoardData *children[99]; // 指向孩子们

} ChessBoardData;
// 初始化所有棋子
Piece **InitSingleChessboard(int positionMax)
{

    Piece **pieces = (Piece **)malloc(sizeof(Piece *) * positionMax * positionMax);
    // 在内存中初始化棋子所占格子
    for (int i = 0; i < positionMax; i++)
    {
        for (int j = 0; j < positionMax; j++)
        {
            *(pieces + i * positionMax + j) = (Piece *)malloc(sizeof(Piece));
        }
    }
    // 连接其中的上下左右
    //  上
    for (int i = 0; i < positionMax; i++)
    {
        for (int j = 0; j < positionMax; j++)
        {
            if (i == 0)
            {
                pieces[i * positionMax + j]->up = NULL;
            }
            else
            {
                pieces[i * positionMax + j]->up = pieces[(i - 1) * positionMax + j];
            }
        }
    }
    // 下
    for (int i = 0; i < positionMax; i++)
    {
        for (int j = 0; j < positionMax; j++)
        {
            if (i == positionMax - 1)
            {
                pieces[i * positionMax + j]->down = NULL;
            }
            else
            {
                pieces[i * positionMax + j]->down = pieces[(i + 1) * positionMax + j];
            }
        }
    }
    // 右
    for (int i = 0; i < positionMax; i++)
    {
        for (int j = 0; j < positionMax; j++)
        {
            if (j == positionMax - 1)
            {
                pieces[i * positionMax + j]->right = NULL;
            }
            else
            {
                pieces[i * positionMax + j]->right = pieces[i * positionMax + j + 1];
            }
        }
    }
    // 左
    for (int i = 0; i < positionMax; i++)
    {
        for (int j = 0; j < positionMax; j++)
        {
            if (j == 0)
            {
                pieces[i * positionMax + j]->left = NULL;
            }
            else
            {
                pieces[i * positionMax + j]->left = pieces[i * positionMax + j - 1];
            }
        }
    }
    for (int i = 0; i < positionMax; i++)
    {
        for (int j = 0; j < positionMax; j++)
        {
            pieces[i * positionMax + j]->state = 0;
            pieces[i * positionMax + j]->qi = 0;
            pieces[i * positionMax + j]->exist = 0;
            pieces[i * positionMax + j]->mesh = 0;
        }
    }
    return pieces;
}
// 硬复制 从fromP 复制到toP
void HardCopyChessboard(Piece **fromP, Piece **toP, int positionMax)
{
    for (int i = 0; i < positionMax; i++)
    {
        for (int j = 0; j < positionMax; j++)
        {
            toP[i * positionMax + j]->qi = fromP[i * positionMax + j]->qi;
            toP[i * positionMax + j]->state = fromP[i * positionMax + j]->state;
            toP[i * positionMax + j]->exist = fromP[i * positionMax + j]->exist;
        }
    }
}
// 申请并初始化棋盘，调用时需要先判断可能性是否大于1，如果小于1，则不要使用该函数。
ChessBoardData *InitChessBoard(int positionMax, struct ChessBoardData *father, int fakeI, int fakeJ)
{
    static int chessBoardN = 0;
    // 动态申请内存，以能够返回对应指针。
    ChessBoardData *this = (ChessBoardData *)malloc(sizeof(ChessBoardData));
    if (father == NULL)
    {
        // 初始化劫争，都置为-1代表初始化时无劫争历史
        this->jiezhengi[0] = -1;
        this->jiezhengi[1] = -1;
        this->jiezhengj[0] = -1;
        this->jiezhengj[1] = -1;
        // 当前棋盘的id，用静态变量来弄
        this->chessBoardN = chessBoardN++;
        // 初始化黑白气总数计数器
        this->meshBlack = 0;
        this->meshWhite = 0;

        // 黑棋先行
        this->state = BLACK;
        // 该棋盘是否有人投降。
        this->IFOneissurrender = UNSURRENDER;
        // 申请一块positionMax*positionMax的棋盘。
        this->chessBoard = InitSingleChessboard(positionMax);
        // 指向自己，方便后续分裂的时候，可以方便的左右切换棋盘。
        this->whiteRight = this;
        this->whiteLeft = this;
        this->blackRight = this;
        this->blackLeft = this;

        // 量子部分初始化。

        // 初始化时，把father传进来。
        this->father = father;
        for (int i = 0; i < 99; i++)
        {
            this->children[i] = NULL;
        }
        this->childrenSum = 0;
        // 初始化可能性计数器

        this->probability = 100;
    }
    else
    {
        // 分裂的虚假棋子基线。
        this->fakepieceI = fakeI;
        this->fakepieceJ = fakeJ;
        // 复制父节点状态
        this->jiezhengi[0] = father->jiezhengi[0];
        this->jiezhengj[0] = father->jiezhengj[0];
        this->jiezhengi[1] = father->jiezhengi[1];
        this->jiezhengj[1] = father->jiezhengj[1];
        // 当前棋盘的id，用静态变量来弄
        this->chessBoardN = chessBoardN++;
        // 复制父亲节点的状态
        this->state = father->state;

        // 复制黑白气总数计数器

        this->meshBlack = father->meshBlack;
        this->meshWhite = father->meshWhite;

        // 该棋盘是否有人投降。
        this->IFOneissurrender = father->IFOneissurrender;
        // 申请一块positionMax*positionMax的棋盘。
        this->chessBoard = InitSingleChessboard(positionMax);
        HardCopyChessboard(father->chessBoard, this->chessBoard, positionMax);

        father->blackRight->blackLeft = this;
        this->blackLeft = father;
        this->blackRight = father->blackRight;
        father->blackRight = this;

        father->whiteRight->whiteLeft = this;
        this->whiteLeft = father;
        this->whiteRight = father->whiteRight;
        father->whiteRight = this;

        // 量子部分初始化。

        // 初始化时，把father传进来。
        this->father = father;
        for (int i = 0; i < 99; i++)
        {
            this->children[i] = NULL;
        }
        // 把孩子节点塞到父亲节点的表里。
        father->children[father->childrenSum] = this;
        father->childrenSum++;
        this->childrenSum = 0;
        // 可能性和基础可能性的初始化，都是父亲节点的一半。
        this->probability = father->probability / 2;
        this->probabilityBase = father->probability / 2;
        father->probability = father->probability / 2 + father->probability % 2;
    }

    return this;
}

// 消除棋盘
void freeSingleChessboard(int positionMax, ChessBoardData *this)
{
    // 左右黑白链表更新。
    this->blackLeft->blackRight = this->blackRight;
    this->blackRight->blackLeft = this->blackLeft;
    this->whiteLeft->whiteRight = this->whiteRight;
    this->whiteRight->whiteLeft = this->whiteLeft;

    // 2.1 父亲节点的子节点删除。
    for (int i = 0; i < this->father->childrenSum; i++)
    {
        if (this->father->children[i] == this)
        {
            for (int j = i + 1; j < this->father->childrenSum; j++)
            {
                // 循环左移覆盖。
                this->father->children[j - 1] = this->father->children[j];
            }
            this->father->childrenSum -= 1;
        }
    }
    // 消除棋盘
    for (int i = 0; i < positionMax; i++)
    {
        for (int j = 0; j < positionMax; j++)
        {
            free(this->chessBoard[i * positionMax + j]);
        }
    }
    free(this->chessBoard);
    free(this);
}

// 气的扩散（递归）
void SpreadQi(Piece *this)
{
    if (this->up != NULL)
    {
        if ((this->up->state == this->state) && (this->qi != this->up->qi))
        {
            this->up->qi = this->qi;
            SpreadQi(this->up);
        }
    }
    if (this->down != NULL)
    {
        if ((this->down->state == this->state) && (this->qi != this->down->qi))
        {
            this->down->qi = this->qi;
            SpreadQi(this->down);
        }
    }
    if (this->left != NULL)
    {
        if ((this->left->state == this->state) && (this->qi != this->left->qi))
        {
            this->left->qi = this->qi;
            SpreadQi(this->left);
        }
    }
    if (this->right != NULL)
    {
        if ((this->right->state == this->state) && (this->qi != this->right->qi))
        {
            this->right->qi = this->qi;
            SpreadQi(this->right);
        }
    }
}

// 由某个节点的状态更新气
void UpdateQiAgainst(State state, Piece *this)
{
    // 找状态相反的子，阻断他们的气，并扩散气。
    if (this->up != NULL)
    {
        if (this->up->state == -state)
        {
            this->up->qi -= 1;
            SpreadQi(this->up);
        }
    }
    if (this->down != NULL)
    {
        if (this->down->state == -state)
        {
            this->down->qi -= 1;
            SpreadQi(this->down);
        }
    }
    if (this->left != NULL)
    {
        if (this->left->state == -state)
        {
            this->left->qi -= 1;
            SpreadQi(this->left);
        }
    }
    if (this->right != NULL)
    {
        if (this->right->state == -state)
        {
            this->right->qi -= 1;
            SpreadQi(this->right);
        }
    }
}
void UpdateQi(State state, Piece *this)
{
    //  上下左右是否有空白
    if (this->up != NULL)
    {
        if (this->up->state == BLANK)
        {
            this->qi += 1;
        }
    }
    if (this->down != NULL)
    {
        if (this->down->state == BLANK)
        {
            this->qi += 1;
        }
    }
    if (this->left != NULL)
    {
        if (this->left->state == BLANK)
        {
            this->qi += 1;
        }
    }
    if (this->right != NULL)
    {
        if (this->right->state == BLANK)
        {
            this->qi += 1;
        }
    }
    // 找状态相同的子，连接他们的气，并扩散气。
    if (this->up != NULL)
    {
        if (this->up->state == this->state)
        {
            this->qi -= 1;
            this->qi += this->up->qi;
        }
    }
    if (this->down != NULL)
    {
        if (this->down->state == this->state)
        {
            this->qi -= 1;
            this->qi += this->down->qi;
        }
    }
    if (this->left != NULL)
    {
        if (this->left->state == this->state)
        {
            this->qi -= 1;
            this->qi += this->left->qi;
        }
    }
    if (this->right != NULL)
    {
        if (this->right->state == this->state)
        {
            this->qi -= 1;
            this->qi += this->right->qi;
        }
    }
    // 传播影响。
    SpreadQi(this);
}
// 提子出现了未存在的点，从上到下消除影响

ChessBoardData *EreaseNotExistchessBoardRecurrence(ChessBoardData *this, int postionMax)
{
    ChessBoardData *res = NULL;
    // 递归:把this的children全部找出来消除掉。
    for (int i = 0; i < this->childrenSum; i++)
    {
        EreaseNotExistchessBoardRecurrence(this->children[i], postionMax);
    }
    // 出口:消除某个具体棋盘
    res = this->blackRight;
    freeSingleChessboard(postionMax, this);
    return res;
}
ChessBoardData *EreaseNotExistchessBoard(ChessBoardData *this, int i, int j, int postionMax)
{
    while ((this->fakepieceI != i) || (this->fakepieceJ != j))
    {
        this = this->father;
    }
    // 2. 父亲可能性+回来。
    this->father->probability += this->probabilityBase;
    ChessBoardData *res = EreaseNotExistchessBoardRecurrence(this, postionMax);

    return res;
}
// 指定棋盘按气提子
ChessBoardData *EraserPiece(ChessBoardData *chessBoardData, int postionMax, State state)
{
    Piece *temp;
    int tempCountNull = 0;
    int tempCountjiezheng = 0;
    ChessBoardData *res = NULL;
    for (int i = 0; i < postionMax; i++)
    {
        for (int j = 0; j < postionMax; j++)
        {
            temp = chessBoardData->chessBoard[i * postionMax + j];
            if (temp->state != BLANK)
            {
                if (temp->qi == 0)
                {
                    temp->mesh = -state;
                    if (state == -1)
                    {
                        chessBoardData->meshWhite -= 1;
                    }
                    else if (state == 1)
                    {
                        chessBoardData->meshBlack -= 1;
                    }
                    if (temp->exist == 0)
                    {
                        res = EreaseNotExistchessBoard(chessBoardData, i, j, postionMax);
                        return res;
                    }
                    if (temp->up != NULL)
                    {
                        if (temp->up->state == -temp->state)
                        {
                            tempCountjiezheng += 1;
                        }
                    }
                    else
                    {
                        tempCountNull += 1;
                    }
                    if (temp->down != NULL)
                    {
                        if (temp->down->state == -temp->state)
                        {
                            tempCountjiezheng += 1;
                        }
                    }
                    else
                    {
                        tempCountNull += 1;
                    }
                    if (temp->right != NULL)
                    {
                        if (temp->right->state == -temp->state)
                        {
                            tempCountjiezheng += 1;
                        }
                    }
                    else
                    {
                        tempCountNull += 1;
                    }
                    if (temp->left != NULL)
                    {
                        if (temp->left->state == -temp->state)
                        {
                            tempCountjiezheng += 1;
                        }
                    }
                    else
                    {
                        tempCountNull += 1;
                    }
                    if (tempCountNull + tempCountjiezheng == 3)
                    {
                        if (state == BLACK)
                        {
                            chessBoardData->jiezhengi[0] = i;
                            chessBoardData->jiezhengj[0] = j;
                        }
                        if (state == WHITE)
                        {
                            chessBoardData->jiezhengi[1] = i;
                            chessBoardData->jiezhengj[1] = j;
                        }
                    }
                    temp->state = BLANK;
                    temp->exist = 0;
                    // 提子会导致气的波动
                    // 找状态相反的子，更新它们的气，并对气进行扩散。
                    if (temp->up != NULL)
                    {
                        if (temp->up->state == state)
                        {
                            temp->up->qi += 1;
                            SpreadQi(temp->up);
                        }
                    }
                    if (temp->down != NULL)
                    {
                        if (temp->down->state == state)
                        {
                            temp->down->qi += 1;
                            SpreadQi(temp->down);
                        }
                    }
                    if (temp->left != NULL)
                    {
                        if (temp->left->state == state)
                        {
                            temp->left->qi += 1;
                            SpreadQi(temp->left);
                        }
                    }
                    if (temp->right != NULL)
                    {
                        if (temp->right->state == state)
                        {
                            temp->right->qi += 1;
                            SpreadQi(temp->right);
                        }
                    }
                }
            }
        }
    }
    return res;
}
// 重新统计该点的目归属。
void UpdateMesh(Piece *this, ChessBoardData *chessBoardData)
{
    if (this->mesh > 0)
    {
        chessBoardData->meshWhite -= 1;
    }
    else if (this->mesh < 0)
    {
        chessBoardData->meshBlack -= 1;
    }
    int sumMesh = 0;
    if (this->up != NULL)
    {
        sumMesh += this->up->state;
    }
    if (this->down != NULL)
    {
        sumMesh += this->down->state;
    }
    if (this->right != NULL)
    {
        sumMesh += this->right->state;
    }
    if (this->left != NULL)
    {
        sumMesh += this->left->state;
    }
    if (sumMesh > 0)
    {
        this->mesh = WHITE;
    }
    else if (sumMesh < 0)
    {
        this->mesh = BLACK;
    }
    else
    {
        this->mesh = BLANK;
    }
    if (this->mesh > 0)
    {
        chessBoardData->meshWhite += 1;
    }
    else if (this->mesh < 0)
    {
        chessBoardData->meshBlack += 1;
    }
}

// 常规步
ChessBoardData *NormalStep(int i, int j, int positionMax, State state, ChessBoardData *chessBoardData)
{
    ChessBoardData *res = NULL;
    // i,j是棋盘位置，state是黑/白，pieces是棋盘。
    // 表示在该棋盘上的ij位置下了一步。
    Piece *this = chessBoardData->chessBoard[i * positionMax + j];

    UpdateQiAgainst(state, this);
    // 如果返回非NULL值，则说明被提的子中存在量子棋观测不存在的情况。
    // 是对某个棋子的判定，需要遍历所有棋盘，找到其中某个棋子为假的点。
    res = EraserPiece(chessBoardData, positionMax, state);
    if (res != NULL)
    {
        return res;
    }
    this->state = state;
    this->qi = 0;
    this->exist = 1;
    if (this->mesh > 0)
    {
        chessBoardData->meshWhite -= 1;
    }
    else if (this->mesh < 0)
    {
        chessBoardData->meshBlack -= 1;
    }
    this->mesh = state;
    if (this->mesh > 0)
    {
        chessBoardData->meshWhite += 1;
    }
    else if (this->mesh < 0)
    {
        chessBoardData->meshBlack += 1;
    }
    if (this->up != NULL)
    {
        if (this->up->state == BLANK)
        {
            UpdateMesh(this->up, chessBoardData);
        }
    }
    if (this->down != NULL)
    {
        if (this->down->state == BLANK)
        {
            UpdateMesh(this->down, chessBoardData);
        }
    }
    if (this->left != NULL)
    {
        if (this->left->state == BLANK)
        {
            UpdateMesh(this->left, chessBoardData);
        }
    }
    if (this->right != NULL)
    {
        if (this->right->state == BLANK)
        {
            UpdateMesh(this->right, chessBoardData);
        }
    }
    UpdateQi(state, this);
    // 如果返回1，则说明被提的子中存在量子棋观测不存在的情况。
    res = EraserPiece(chessBoardData, positionMax, state);
    if (res != NULL)
    {
        return res;
    }

    if (chessBoardData->IFOneissurrender == BLACKSURRENDER)
    {
        chessBoardData->state = WHITE;
    }
    else if (chessBoardData->IFOneissurrender == WHITESURRENDER)
    {
        chessBoardData->state = BLACK;
    }
    else
    {
        chessBoardData->state = -chessBoardData->state;
    }

    return res;
}

// 量子步，
ChessBoardData *QuantumStep(MultiThreadData *dataP, State state, ChessBoardData *father)
{

    ChessBoardData *res;

    // 随机一个0-99的整数，来判断该子的具体存在。
    if ((rand() % 100) < 50) // 这里可以再用一个随机数来决定哪个棋盘在左面，这样就不会被棋手察觉哪个是真。
    {

        // 新申请一个动态内存，硬复制目前的所有状态。
        ChessBoardData *child = InitChessBoard(dataP->positionMax, father, dataP->positionILast, dataP->positionJLast);
        res = NormalStep(dataP->positionI, dataP->positionJ, dataP->positionMax, state, father);
        NormalStep(dataP->positionILast, dataP->positionJLast, dataP->positionMax, state, child);
        child->chessBoard[dataP->positionILast * dataP->positionMax + dataP->positionJLast]->exist = 0;
    }
    else
    {

        // 新申请一个动态内存，硬复制目前的所有状态。
        ChessBoardData *child = InitChessBoard(dataP->positionMax, father, dataP->positionI, dataP->positionJ);
        res = NormalStep(dataP->positionILast, dataP->positionJLast, dataP->positionMax, state, father);
        NormalStep(dataP->positionI, dataP->positionJ, dataP->positionMax, state, child);
        child->chessBoard[dataP->positionI * dataP->positionMax + dataP->positionJ]->exist = 0;
    }
    return res;
}
// 终端显示棋盘
void ShowChessboard(MultiThreadData *whiteDataP, MultiThreadData *blackDataP, int positionMax, ChessBoardData *whiteP, ChessBoardData *blackP)
{
    system("cls");
    // 第一行棋子类型。
    printf("玩家一：白 棋子：O");
    for (int i = 0; i < positionMax * 5 - 17; i++)
    {
        printf(" ");
    }
    printf("玩家二：黑 棋子：X\n");
    printf("");

    // 输出当前棋盘编号
    if (whiteP != NULL)
    {
        printf("No.%2d:%3d%%", whiteP->chessBoardN, whiteP->probability);
    }
    else
    {
        printf("No.-1");
    }
    for (int i = 0; i < positionMax * 5 - 9; i++)
    {
        printf(" ");
    }
    if (blackP != NULL)
    {
        printf("No.%2d:%3d%%\n", blackP->chessBoardN, blackP->probability);
    }
    else
    {
        printf("No.-1\n");
    }

    if (whiteP != NULL)
    {
        if (whiteP->state == BLACK)
        {
            printf("等待对方落子");
        }
        else
        {
            printf("当前该你落子");
        }
    }
    else
    {
        printf("你已停止所有操作，请等待对方结束后游戏结束。");
    }
    for (int i = 0; i < positionMax * 5 - 11; i++)
    {
        printf(" ");
    }
    if (blackP != NULL)
    {
        if (blackP->state == WHITE)
        {
            printf("等待对方落子\n");
        }
        else
        {
            printf("当前该你落子\n");
        }
    }
    else
    {
        printf("你已停止所有操作，请等待对方结束后游戏结束。\n");
    }

    if (whiteP != NULL)
    {
        printf("白目：%-3d 黑目：%-3d", whiteP->meshWhite, whiteP->meshBlack);
    }
    else
    {
        printf("                    ");
    }
    for (int i = 0; i < positionMax * 5 - 18; i++)
    {
        printf(" ");
    }
    if (blackP != NULL)
    {
        printf("白目：%-3d 黑目：%-3d\n", blackP->meshWhite, blackP->meshBlack);
    }
    else
    {
        printf("                    \n");
    }
    // 输出打头。("----")4*max+(' ')1*max+("----")4*max+'\n'
    printf("-");
    for (int i = 0; i < positionMax; i++)
    {
        printf("----");
    }
    for (int i = 0; i < positionMax; i++)
    {
        printf(" ");
    }
    printf("-");
    for (int i = 0; i < positionMax; i++)
    {
        printf("----");
    }
    printf("\n");
    // 输出两行。
    for (int i = 0; i < positionMax; i++)
    {
        // 输出行头标
        printf("|");
        for (int j = 0; j < positionMax; j++)
        {
            if (whiteP != NULL)
            {
                if ((i == whiteDataP->positionI) && (j == whiteDataP->positionJ))
                {
                    printf("*");
                }
                else
                {
                    printf(" ");
                }
                if ((i == whiteDataP->positionILast) && (j == whiteDataP->positionJLast))
                {
                    printf("#");
                }
                else
                {
                    printf(" ");
                }
                switch (whiteP->chessBoard[i * positionMax + j]->state)
                {
                case BLANK:
                    printf(" |");
                    break;
                case BLACK:
                    printf("X|");
                    break;
                case WHITE:
                    printf("O|");
                    break;
                }
            }
            else
            {
                printf("    ");
            }
        }
        for (int j = 0; j < positionMax; j++)
        {
            printf(" ");
        }
        printf("|");
        for (int j = 0; j < positionMax; j++)
        {
            if (blackP != NULL)
            {
                if ((i == blackDataP->positionI) && (j == blackDataP->positionJ))
                {
                    printf("*");
                }
                else
                {
                    printf(" ");
                }
                if ((i == blackDataP->positionILast) && (j == blackDataP->positionJLast))
                {
                    printf("#");
                }
                else
                {
                    printf(" ");
                }
                switch (blackP->chessBoard[i * positionMax + j]->state)
                {
                case BLANK:
                    printf(" |");
                    break;
                case BLACK:
                    printf("X|");
                    break;
                case WHITE:
                    printf("O|");
                    break;
                }
            }
            else
            {
                printf("    ");
            }
        }
        // 临时使用
        // printf("\t\t");
        // for(int j=0;j<positionMax;j++)
        // {
        //     printf(" %2d|",blackP->chessBoard[i*positionMax+j]->mesh);
        // }

        // 以上临时使用
        printf("\n");
        printf("-");
        for (int i = 0; i < positionMax; i++)
        {
            printf("----");
        }
        for (int j = 0; j < positionMax; j++)
        {
            printf(" ");
        }
        printf("-");
        for (int i = 0; i < positionMax; i++)
        {
            printf("----");
        }
        printf("\n");
    }

    printf("g<     >h");
    for (int i = 0; i < positionMax * 5 - 8; i++)
    {
        printf(" ");
    }
    printf(";<     >\'\n");

    printf("常规v   量子b");
    for (int i = 0; i < positionMax * 5 - 12; i++)
    {
        printf(" ");
    }
    printf("常规.    量子/\n");
    printf("投降 c");
    for (int i = 0; i < positionMax * 5 - 5; i++)
    {
        printf(" ");
    }
    printf("投降,");
}

// 获取键盘输入(多线程),弃用
void GetKeyboardInputWhite(void *arg)
{
    MultiThreadData *dataP = (MultiThreadData *)arg;
    char ch = '0';
    while (1)
    {
        Sleep(10);
        if (kbhit())
        {
            ch = getch();
            if (ch == 'g')
            {
                dataP->signMoveChessboard -= 1;
            }
            else if (ch == 'h')
            {
                dataP->signMoveChessboard += 1;
            }
            else if (ch == 'v')
            {
                dataP->signMove = 1;
            }
            else if (ch == 'b')
            {
                dataP->signMoveQuantum = 1;
            }
            else if (ch == 'w')
            {
                dataP->positionI -= 1;
                dataP->positionI += dataP->positionMax;
                dataP->positionI %= dataP->positionMax;
            }
            else if (ch == 's')
            {
                dataP->positionI += 1;
                dataP->positionI %= dataP->positionMax;
            }
            else if (ch == 'a')
            {
                dataP->positionJ -= 1;
                dataP->positionJ += dataP->positionMax;
                dataP->positionJ %= dataP->positionMax;
            }
            else if (ch == 'd')
            {
                dataP->positionJ -= 1;
                dataP->positionJ += dataP->positionMax;
                dataP->positionJ %= dataP->positionMax;
            }
        }
    }
}
void GetKeyboardInputBlack(void *arg)
{
    MultiThreadData *dataP = (MultiThreadData *)arg;
    char ch = '0';
    while (1)
    {
        Sleep(10);
        if (kbhit())
        {
            ch = getch();
            if (ch == ';')
            {

                dataP->signMoveChessboard -= 1;
            }
            else if (ch == '\'')
            {
                dataP->signMoveChessboard += 1;
            }
            else if (ch == '.')
            {
                dataP->signMove = 1;
            }
            else if (ch == '/')
            {
                dataP->signMoveQuantum = 1;
            }
            else if (ch == 72)
            {
                dataP->positionI -= 1;
                dataP->positionI += dataP->positionMax;
                dataP->positionI %= dataP->positionMax;
            }
            else if (ch == 80)
            {
                dataP->positionI += 1;
                dataP->positionI %= dataP->positionMax;
            }
            else if (ch == 75)
            {
                dataP->positionJ -= 1;
                dataP->positionJ += dataP->positionMax;
                dataP->positionJ %= dataP->positionMax;
            }
            else if (ch == 77)
            {
                dataP->positionJ -= 1;
                dataP->positionJ += dataP->positionMax;
                dataP->positionJ %= dataP->positionMax;
            }
        }
    }
}
// 获取键盘输入
void GetKeyboardInput(MultiThreadData *blackDataP, MultiThreadData *whiteDataP)
{
    char ch;
    while (1)
    {
        if (kbhit())
        {
            ch = getch();
            if (ch == ';')
            {
                blackDataP->signMoveChessboard -= 1;
                break;
            }
            else if (ch == '\'')
            {
                blackDataP->signMoveChessboard += 1;
                break;
            }
            else if (ch == '.')
            {
                blackDataP->signMove = 1;
                break;
            }
            else if (ch == '/')
            {
                blackDataP->signMoveQuantum = 1;
                break;
            }
            else if (ch == 72)
            {
                blackDataP->positionI -= 1;
                blackDataP->positionI += blackDataP->positionMax;
                blackDataP->positionI %= blackDataP->positionMax;
                break;
            }
            else if (ch == 80)
            {
                blackDataP->positionI += 1;
                blackDataP->positionI %= blackDataP->positionMax;
                break;
            }
            else if (ch == 75)
            {
                blackDataP->positionJ -= 1;
                blackDataP->positionJ += blackDataP->positionMax;
                blackDataP->positionJ %= blackDataP->positionMax;
                break;
            }
            else if (ch == 77)
            {
                blackDataP->positionJ += 1;
                blackDataP->positionJ %= blackDataP->positionMax;
                break;
            }
            else if (ch == ',')
            {
                whiteDataP->iswin = 1;
                break;
            }

            else if (ch == 'g')
            {
                whiteDataP->signMoveChessboard -= 1;
                break;
            }
            else if (ch == 'h')
            {
                whiteDataP->signMoveChessboard += 1;
                break;
            }
            else if (ch == 'v')
            {
                whiteDataP->signMove = 1;
                break;
            }
            else if (ch == 'b')
            {
                whiteDataP->signMoveQuantum = 1;
                break;
            }
            else if (ch == 'w')
            {
                whiteDataP->positionI -= 1;
                whiteDataP->positionI += whiteDataP->positionMax;
                whiteDataP->positionI %= whiteDataP->positionMax;
                break;
            }
            else if (ch == 's')
            {
                whiteDataP->positionI += 1;
                whiteDataP->positionI %= whiteDataP->positionMax;
                break;
            }
            else if (ch == 'a')
            {
                whiteDataP->positionJ -= 1;
                whiteDataP->positionJ += whiteDataP->positionMax;
                whiteDataP->positionJ %= whiteDataP->positionMax;
                break;
            }
            else if (ch == 'd')
            {
                whiteDataP->positionJ += 1;
                whiteDataP->positionJ %= whiteDataP->positionMax;
                break;
            }
            else if (ch == 'c')
            {
                blackDataP->iswin = 1;
                break;
            }
        }
    }
}
// 落子判定
int JudgeMove(int i, int j, int positionMax, State state, ChessBoardData *chessBoardData)
{
    if (chessBoardData->state == state) // 判断是不是我落子
    {
        if (chessBoardData->chessBoard[i * positionMax + j]->state == BLANK) // 判断落子位置是否是空的
        {
            if (state == BLACK)
            {
                if (!((i == chessBoardData->jiezhengi[1]) && (j == chessBoardData->jiezhengj[1])))
                {
                    return 1;
                }
                else
                {
                    return 0;
                }
            }
            if (state == WHITE)
            {
                if (!((i == chessBoardData->jiezhengi[0]) && (j == chessBoardData->jiezhengj[0])))
                {
                    return 1;
                }
                else
                {
                    return 0;
                }
            }
        }
        else
        {
            return 0;
        }
    }
    else
    {
        return 0;
    }
}

// 申请多线程使用的数据
MultiThreadData *InitMultThreadData(int positionMax)
{
    MultiThreadData *DataP = (MultiThreadData *)malloc(sizeof(MultiThreadData));
    DataP->signMoveChessboard = 0;
    DataP->positionI = 0;
    DataP->positionJ = 0;
    DataP->positionILast = -1;
    DataP->positionJLast = -1;
    DataP->signMove = 0;
    DataP->signMoveQuantum = 0;
    DataP->positionMax = positionMax;
    DataP->iswin = 0;
}

int CountWinnerWhite(ChessBoardData *this)
{
    int sum = 0;
    int i = 0;
    for (i = 0; i < this->childrenSum; i++)
    {
        sum += CountWinnerWhite(this->children[i]);
    }
    return this->probability * this->meshWhite;
}
int CountWinnerBlack(ChessBoardData *this)
{
    int sum = 0;
    int i = 0;
    for (i = 0; i < this->childrenSum; i++)
    {
        sum += CountWinnerBlack(this->children[i]);
    }
    return this->probability * this->meshBlack;
}
// 统计胜利者
WINNER CountWinner(ChessBoardData *mainP)
{
    int whiteMesh = CountWinnerWhite(mainP);
    int blackMesh = CountWinnerBlack(mainP);
    if (whiteMesh >= blackMesh)
    {
        return WHITEISWINNER;
    }
    else
    {
        return BLACKISWINNER;
    }
}
void DeleteChessBoard(ChessBoardData *this, int positionMax)
{
    for (int i = 0; i < this->childrenSum; i++)
    {
        DeleteChessBoard(this->children[i], positionMax);
    }
    if (this->blackLeft != NULL && this->whiteLeft != NULL)
    {
        freeSingleChessboard(positionMax, this);
    }
    else
    {
        for (int i = 0; i < positionMax; i++)
        {
            for (int j = 0; j < positionMax; j++)
            {
                free(this->chessBoard[i * positionMax + j]);
            }
        }
        free(this->chessBoard);
        free(this);
    }
}
int main()
{
    // 中文编码调整
    SetConsoleOutputCP(65001);
    // 键入棋盘大小
    int positionMax;
    int signJiezhengBlack;
    int signJiezhengWhite;
    printf("请输入棋盘大小");
    scanf("%d", &positionMax);
    // 种随机数种子
    srand((unsigned)time(NULL));
    // 初始化棋盘
    ChessBoardData *mainP = InitChessBoard(positionMax, NULL, 0, 0); // 真实棋盘，棋子恒为真
    ChessBoardData *whiteP = mainP;                                  // 白色当前展示棋盘
    ChessBoardData *blackP = mainP;                                  // 黑色当前展示棋盘
    ChessBoardData *tempP;
    ChessBoardData *tempShow; // 保存量子步/常规步返回的目前展示棋盘，
    // 初始化接收键盘的线程-黑-白(弃用)
    // 初始化跟键盘交互需要的数据。
    // HANDLE black, white;
    MultiThreadData *blackDataP = InitMultThreadData(positionMax);
    // black = (HANDLE)_beginthread(GetKeyboardInputWhite, 0, blackDataP);
    MultiThreadData *whiteDataP = InitMultThreadData(positionMax);
    // white = (HANDLE)_beginthread(GetKeyboardInputBlack, 0, whiteDataP);
    WINNER winner = UNKNOW;
    while (winner == UNKNOW)
    {
        ShowChessboard(whiteDataP, blackDataP, positionMax, whiteP, blackP);
        GetKeyboardInput(blackDataP, whiteDataP);
        // 移动白棋显示棋盘
        if (whiteDataP->iswin)
        {
            // 把黑棋当前棋盘指向下一个棋盘
            blackP->IFOneissurrender = BLACKSURRENDER;
            tempP = blackP;
            tempP->blackLeft->blackRight = tempP->blackRight;
            tempP->blackRight->blackLeft = tempP->blackLeft;
            blackP = tempP->blackRight;
            tempP->blackRight = NULL;
            tempP->blackLeft = NULL;
            if (tempP == blackP)
            {
                blackP = NULL;
            }
            whiteDataP->iswin = 0;
        }
        if (blackDataP->iswin)
        {
            whiteP->IFOneissurrender = WHITESURRENDER;
            tempP = whiteP;
            tempP->whiteLeft->whiteRight = tempP->whiteRight;
            tempP->whiteRight->whiteLeft = tempP->whiteLeft;
            whiteP = tempP->whiteRight;
            tempP->whiteRight = NULL;
            tempP->whiteLeft = NULL;
            if (tempP == whiteP)
            {
                whiteP = NULL;
            }
            blackDataP->iswin = 0;
        }
        if (blackP == NULL && whiteP == NULL)
        {
            // 游戏结束，统计存活棋盘的目数和可能性。这里还缺一个比如黑棋指针为空的展示。
            winner = CountWinner(mainP);
            break;
        }
        if (whiteDataP->signMoveChessboard != 0)
        {
            if (whiteDataP->signMoveChessboard == 1)
            {
                whiteP = whiteP->whiteRight;
                whiteDataP->signMoveChessboard -= 1;
            }
            else
            {
                whiteP = whiteP->whiteLeft;
                whiteDataP->signMoveChessboard += 1;
            }
        }

        // 移动黑棋显示棋盘
        if (blackDataP->signMoveChessboard != 0)
        {
            if (blackDataP->signMoveChessboard == 1)
            {
                blackP = blackP->blackRight;
                blackDataP->signMoveChessboard -= 1;
            }
            else
            {
                blackP = blackP->blackLeft;
                blackDataP->signMoveChessboard += 1;
            }
        }

        // 白棋落子判定
        if (whiteDataP->signMove == 1)
        {

            if (JudgeMove(whiteDataP->positionI, whiteDataP->positionJ, whiteDataP->positionMax, WHITE, whiteP))
            {
                tempShow = NormalStep(whiteDataP->positionI, whiteDataP->positionJ, whiteDataP->positionMax, WHITE, whiteP);
                if (tempShow != NULL)
                {
                    whiteP = tempShow;
                    if (blackP != NULL)
                    {
                        blackP = tempShow;
                    }
                }
                whiteDataP->signMove = 0;
                whiteP->jiezhengi[0] = -1;
                whiteP->jiezhengj[0] = -1;
                // 白棋落子会把未完成的量子步顶掉
                whiteDataP->positionILast = -1;
                whiteDataP->positionJLast = -1;
            }
            else
            {
                whiteDataP->signMove = 0;
            }
        }

        // 黑棋落子判定
        if (blackDataP->signMove == 1)
        {
            if (JudgeMove(blackDataP->positionI, blackDataP->positionJ, blackDataP->positionMax, BLACK, blackP))
            {
                tempShow = NormalStep(blackDataP->positionI, blackDataP->positionJ, blackDataP->positionMax, BLACK, blackP);
                if (tempShow != NULL)
                {
                    if (whiteP != NULL)
                    {
                        whiteP = tempShow;
                    }
                    blackP = tempShow;
                }
                blackDataP->signMove = 0;
                blackP->jiezhengi[1] = -1;
                blackP->jiezhengj[1] = -1;
                blackDataP->positionILast = -1;
                blackDataP->positionJLast = -1;
            }
            else
            {
                blackDataP->signMove = 0;
            }
        }

        // 白棋量子落子
        if (whiteDataP->signMoveQuantum == 1)
        {
            // 可能性大于1，才能落量子步，否则按无效输入处理
            if (whiteP->probability > 1)
            {
                if (JudgeMove(whiteDataP->positionI, whiteDataP->positionJ, whiteDataP->positionMax, WHITE, whiteP))
                {
                    if (whiteDataP->positionILast == -1)
                    {
                        whiteDataP->positionILast = whiteDataP->positionI;
                        whiteDataP->positionJLast = whiteDataP->positionJ;
                    }
                    else
                    {
                        if ((whiteDataP->positionILast != whiteDataP->positionI) || (whiteDataP->positionJLast != whiteDataP->positionJ))
                        {
                            tempShow = QuantumStep(whiteDataP, WHITE, whiteP);
                            if (tempShow != NULL)
                            {
                                whiteP = tempShow;
                                blackP = tempShow;
                            }
                            whiteDataP->positionILast = -1;
                            whiteDataP->positionJLast = -1;
                            whiteP->jiezhengi[0] = -1;
                            whiteP->jiezhengj[0] = -1;
                        }
                    }
                    // 告诉键盘接收端，我已经把这个信息读入了。
                    whiteDataP->signMoveQuantum = 0;
                }
                else
                {
                    // 告诉键盘接收端，你不能在这个地方落子，所以操作无效。
                    whiteDataP->signMoveQuantum = 0;
                }
            }
            else
            {
                // 告诉键盘接收端，不能再对棋盘做细分了，所以操作无效。
                whiteDataP->signMoveQuantum = 0;
            }
        }
        // 黑棋量子落子
        if (blackDataP->signMoveQuantum == 1)
        {
            if (JudgeMove(blackDataP->positionI, blackDataP->positionJ, blackDataP->positionMax, BLACK, blackP))
            {
                if (blackDataP->positionILast == -1)
                {
                    blackDataP->positionILast = blackDataP->positionI;
                    blackDataP->positionJLast = blackDataP->positionJ;
                }
                else
                {
                    if ((blackDataP->positionILast != blackDataP->positionI) || (blackDataP->positionJLast != blackDataP->positionJ))
                    {
                        tempShow = QuantumStep(blackDataP, BLACK, blackP);
                        if (tempShow != NULL)
                        {
                            whiteP = tempShow;
                            blackP = tempShow;
                        }
                        blackDataP->positionILast = -1;
                        blackDataP->positionJLast = -1;
                        blackP->jiezhengi[1] = -1;
                        blackP->jiezhengj[1] = -1;
                    }
                }

                blackDataP->signMoveQuantum = 0;
            }
            else
            {
                blackDataP->signMoveQuantum = 0;
            }
        }
        Sleep(5);
    }
    system("cls");
    if (winner == BLACKISWINNER)
    {
        printf("Black is Winner!\n");
        system("pause");
    }
    else
    {
        printf("White is Winner!\n");
        system("pause");
    }
    free(blackDataP);
    free(whiteDataP);
    DeleteChessBoard(mainP, positionMax);

    return 0;
}